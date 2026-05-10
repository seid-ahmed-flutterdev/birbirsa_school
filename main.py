import os
import sys
import json
import time
import mimetypes
import threading
import re

try:
    import fcntl  # Linux/Mac only (Render). Not available on Windows.
except ImportError:
    fcntl = None  # Windows local dev — file lock guard is skipped

# Fix Windows console encoding (emoji crash prevention)
if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

from datetime import datetime
from flask import Flask, request, jsonify, Response, stream_with_context, send_from_directory
from flask_cors import CORS
import telebot
from telebot import types
import requests
from urllib.parse import quote, urlparse

# ─────────────────────────────────────────────────────────────
#  CONFIG & PATHS
#  On Render: uses /data (persistent disk) for data + media
#  Locally:   uses ./data and ./media
# ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

IS_RENDER = bool(os.environ.get('RENDER'))
# Free plan: always use the app's own writable directory (no disk mount needed)
DATA_DIR  = os.path.join(BASE_DIR, 'data')
MEDIA_DIR = os.path.join(BASE_DIR, 'media')

DATA_FILE = os.path.join(DATA_DIR, 'content.json')
REG_FILE  = os.path.join(DATA_DIR, 'registrations.json')
WEB_DIR   = os.path.realpath(os.path.join(BASE_DIR, 'build', 'web'))

os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(MEDIA_DIR, exist_ok=True)

PORT             = int(os.environ.get('PORT', 3000))
ADVERT_BOT_TOKEN = os.environ.get('ADVERT_BOT_TOKEN', '8704157930:AAE8Q1Y_dKgIjPbdOBetsefPGAokNJLLoZo')
SCHOOL_BOT_TOKEN = os.environ.get('SCHOOL_BOT_TOKEN', '8363076420:AAEZ78VfLhgjLBFlzAEjvqf1jt10A30TPGU')
DIRECTOR_CHAT_ID = os.environ.get('DIRECTOR_CHAT_ID', '8319751158')

# Bot running state — defined here so Flask routes can safely read it
_bots_started = False

mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('application/json', '.json')
mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('text/css', '.css')

app = Flask(__name__, static_folder=WEB_DIR, static_url_path='')
CORS(app, resources={r"/api/*": {"origins": "*"}})


# ── DATABASE HELPERS ──
def read_json(path):
    try:
        if not os.path.exists(path): return []
        with open(path, 'r', encoding='utf-8') as f: return json.load(f)
    except: return []

def write_json(path, data):
    try:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception as e: print(f"❌ DB Write Error: {e}")

# ─────────────────────────────────────────────────────────────
#  FLASK ROUTES (Website & API)
# ─────────────────────────────────────────────────────────────
@app.route('/')
def index_route(): return send_from_directory(WEB_DIR, 'index.html')

@app.route('/<path:path>')
def static_proxy(path): return send_from_directory(WEB_DIR, path)

@app.route('/api/content', methods=['GET'])
def get_content_api(): return jsonify(read_json(DATA_FILE))

@app.route('/api/registrations', methods=['GET'])
def get_registrations_api(): return jsonify(read_json(REG_FILE))

@app.route('/health', methods=['GET'])
def health_check():
    """Render health check — confirms server + bots are alive."""
    regs    = read_json(REG_FILE)
    content = read_json(DATA_FILE)
    return jsonify({
        "status": "ok",
        "bots": "running" if _bots_started else "starting",
        "registrations": len(regs),
        "content_items": len(content),
        "storage": "render_disk" if IS_RENDER else "local",
        "timestamp": datetime.now().isoformat()
    })

@app.route('/api/registrations/search', methods=['GET'])
def search_registrations_api():
    """Search registrations by name, phone, or ID"""
    q = request.args.get('q', '').lower().strip()
    if not q:
        return jsonify({"results": [], "error": "missing query"}), 400
    regs = read_json(REG_FILE)
    results = [r for r in regs if (
        q in r.get('name', '').lower() or
        q in r.get('phone', '') or
        q in r.get('reg_id', '').lower() or
        q in r.get('details', '').lower()
    )]
    print(f"🔍 Search '{q}': {len(results)} results from {len(regs)} total records")
    return jsonify({"results": results})

# ─────────────────────────────────────────────────────────────
#  DELETE CONTENT
# ─────────────────────────────────────────────────────────────
@app.route('/api/content/delete', methods=['POST', 'OPTIONS'])
def delete_content_api():
    if request.method == 'OPTIONS':
        return Response('', 200, headers={'Access-Control-Allow-Origin': '*',
                                           'Access-Control-Allow-Headers': 'Content-Type'})
    try:
        data = request.get_json(force=True)
        message_id = data.get('message_id')
        if message_id is None:
            return jsonify({"error": "missing message_id"}), 400

        content = read_json(DATA_FILE)
        original_len = len(content)
        content = [c for c in content if c.get('message_id') != message_id]

        if len(content) < original_len:
            write_json(DATA_FILE, content)
            print(f"🗑️ Deleted content with message_id={message_id}")
            return jsonify({"success": True, "deleted": message_id})
        else:
            return jsonify({"error": "not found", "message_id": message_id}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ─────────────────────────────────────────────────────────────
#  MEDIA PROXY — streams Telegram files (fixes CORS for PDFs, videos)
# ─────────────────────────────────────────────────────────────
@app.route('/api/proxy', methods=['GET', 'OPTIONS'])
def media_proxy():
    if request.method == 'OPTIONS':
        return Response('', 200, headers={'Access-Control-Allow-Origin': '*'})
    
    file_id = request.args.get('file_id')
    if not file_id: return "Missing file_id", 400
    
    token = ADVERT_BOT_TOKEN
    try:
        f_info = telebot.TeleBot(ADVERT_BOT_TOKEN).get_file(file_id)
    except:
        try:
            f_info = telebot.TeleBot(SCHOOL_BOT_TOKEN).get_file(file_id)
            token = SCHOOL_BOT_TOKEN
        except: return "Not found on Telegram", 404
        
    f_url = f"https://api.telegram.org/file/bot{token}/{f_info.file_path}"
    resp = requests.get(f_url, stream=True, timeout=60)
    
    out = Response(stream_with_context(resp.iter_content(8192)), status=resp.status_code)
    out.headers['Content-Type'] = resp.headers.get('Content-Type', 'application/octet-stream')
    out.headers['Access-Control-Allow-Origin'] = '*'
    out.headers['Cache-Control'] = 'public, max-age=3600'  # Cache images 1 hour in browser
    
    if '.pdf' in f_info.file_path.lower():
        out.headers['Content-Type'] = 'application/pdf'
        out.headers['Content-Disposition'] = 'inline'
    
    return out

# ─────────────────────────────────────────────────────────────
#  REGISTRATION / PAYMENT
# ─────────────────────────────────────────────────────────────
@app.route('/api/notify-registration', methods=['POST', 'OPTIONS'])
def web_registration_api():
    """Unified API for Registration/Payment uploads from Flutter Web"""
    if request.method == 'OPTIONS':
        return Response('', 200, headers={'Access-Control-Allow-Origin': '*',
                                           'Access-Control-Allow-Headers': 'Content-Type'})
    try:
        if request.content_type and 'application/json' in request.content_type:
            data   = request.get_json(force=True) or {}
            name   = data.get('name', 'Unknown')
            phone  = data.get('phone', '')
            reg_id = data.get('reg_id', '')
            details = data.get('details', '')
            rtype  = data.get('type', 'registration')
        else:
            name   = request.form.get('name', 'Unknown')
            phone  = request.form.get('phone', '')
            reg_id = request.form.get('reg_id', '')
            details = request.form.get('details', '')
            rtype  = request.form.get('type', 'registration')
        
        saved_files = []
        saved_paths = []
        if 'photos' in request.files:
            for f in request.files.getlist('photos'):
                fname = f"reg_{int(time.time())}_{f.filename}"
                fpath = os.path.join(MEDIA_DIR, fname)
                f.save(fpath)
                saved_files.append(fname)
                saved_paths.append(fpath)
        if 'docs' in request.files:
            for f in request.files.getlist('docs'):
                fname = f"doc_{int(time.time())}_{f.filename}"
                fpath = os.path.join(MEDIA_DIR, fname)
                f.save(fpath)
                saved_files.append(fname)
                saved_paths.append(fpath)
        
        regs = read_json(REG_FILE)
        regs.insert(0, {
            "name": name, "phone": phone, "reg_id": reg_id,
            "details": details, "type": rtype, "photo": ",".join(saved_files),
            "date": datetime.now().isoformat()
        })
        write_json(REG_FILE, regs[:2000])
        print(f"✅ Registration saved: {name} ({rtype}) with {len(saved_files)} files")
        
        bot = telebot.TeleBot(SCHOOL_BOT_TOKEN)
        clean_phone = re.sub(r'[^0-9+]', '', phone)
        
        msg_text  = f"🆕 *WEB SUBMISSION: {rtype.upper()}*\n"
        msg_text += f"───────────────────\n"
        msg_text += f"👤 *Name:* {name}\n"
        msg_text += f"📞 *Phone:* {phone}\n"
        msg_text += f"🆔 *ID:* {reg_id}\n"
        msg_text += f"📅 *Date:* {datetime.now().strftime('%Y-%m-%d')}\n\n"
        msg_text += f"📋 *Details:*\n{details}"

        markup = types.InlineKeyboardMarkup()
        if clean_phone:
            markup.row(
                types.InlineKeyboardButton("📞 Call", url=f"https://wa.me/{clean_phone}"),
                types.InlineKeyboardButton("💬 Copy Phone", url=f"https://t.me/share/url?url={clean_phone}&text=Phone+number")
            )
        
        if saved_paths:
            try:
                first_path = saved_paths[0]
                caption = msg_text[:1024]
                if first_path.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic')):
                    with open(first_path, 'rb') as photo:
                        bot.send_photo(DIRECTOR_CHAT_ID, photo, caption=caption, parse_mode='Markdown', reply_markup=markup)
                else:
                    with open(first_path, 'rb') as doc:
                        bot.send_document(DIRECTOR_CHAT_ID, doc, caption=caption, parse_mode='Markdown', reply_markup=markup)
                for extra_path in saved_paths[1:]:
                    try:
                        if extra_path.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic')):
                            with open(extra_path, 'rb') as photo:
                                bot.send_photo(DIRECTOR_CHAT_ID, photo)
                        else:
                            with open(extra_path, 'rb') as doc:
                                bot.send_document(DIRECTOR_CHAT_ID, doc)
                    except: pass
            except Exception as te:
                bot.send_message(DIRECTOR_CHAT_ID, msg_text, parse_mode='Markdown', reply_markup=markup)
        else:
            bot.send_message(DIRECTOR_CHAT_ID, msg_text, parse_mode='Markdown', reply_markup=markup)
        
        return jsonify({"success": True, "id": reg_id})
    except Exception as e:
        print(f"❌ Registration error: {e}")
        return jsonify({"error": str(e)}), 500

# ─────────────────────────────────────────────────────────────
#  ADVERT BOT — Director sends content → saved → shows on website
# ─────────────────────────────────────────────────────────────
def run_advert_bot_loop():
    while True:
        try:
            bot = telebot.TeleBot(ADVERT_BOT_TOKEN)
            bot.remove_webhook()
            time.sleep(2)

            @bot.message_handler(commands=['start'])
            def advert_start(message):
                if str(message.chat.id) != DIRECTOR_CHAT_ID:
                    bot.reply_to(message, "⛔ Access denied.")
                    return
                bot.reply_to(message,
                    "🎬 *Advert Bot Ready!*\n\n"
                    "Send me any of these to post on the website:\n"
                    "📷 Photo\n🎥 Video (normal or round)\n"
                    "📄 PDF / Document\n🎵 Audio\n💬 Text message\n\n"
                    "I will save it and show it on the school website instantly!",
                    parse_mode='Markdown'
                )

            @bot.message_handler(commands=['delete'])
            def advert_delete(message):
                if str(message.chat.id) != DIRECTOR_CHAT_ID: return
                content = read_json(DATA_FILE)
                if not content:
                    bot.reply_to(message, "📭 No content to delete.")
                    return
                # Show list of last 5 items with their IDs
                lines = ["🗑️ *Last 5 posts (reply /del_ID to delete):*\n"]
                for i, item in enumerate(content[:5]):
                    lines.append(f"{i+1}. [{item['type'].upper()}] {str(item.get('title',''))[:40]} — ID:{item.get('message_id','?')}")
                bot.reply_to(message, "\n".join(lines), parse_mode='Markdown')

            @bot.message_handler(commands=['list'])
            def advert_list(message):
                if str(message.chat.id) != DIRECTOR_CHAT_ID: return
                content = read_json(DATA_FILE)
                if not content:
                    bot.reply_to(message, "📭 Website has no content yet.")
                    return
                lines = [f"📋 *{len(content)} items on website:*\n"]
                for i, item in enumerate(content[:10]):
                    lines.append(f"{i+1}. [{item['type'].upper()}] {str(item.get('title',''))[:50]}")
                bot.reply_to(message, "\n".join(lines), parse_mode='Markdown')

            @bot.message_handler(content_types=['text', 'photo', 'video', 'video_note', 'document', 'audio'])
            def handle_advert_post(message):
                if str(message.chat.id) != DIRECTOR_CHAT_ID:
                    bot.reply_to(message, "⛔ Only the school director can post content.")
                    return

                content  = read_json(DATA_FILE)
                type_str = 'text'
                f_id     = None
                direct_url = None

                if message.photo:
                    type_str, f_id = 'image', message.photo[-1].file_id
                elif message.video:
                    type_str, f_id = 'video', message.video.file_id
                elif message.video_note:
                    type_str, f_id = 'video', message.video_note.file_id  # round video
                elif message.document:
                    mime = message.document.mime_type or ''
                    type_str = 'pdf' if 'pdf' in mime else 'doc'
                    f_id = message.document.file_id
                elif message.audio:
                    type_str, f_id = 'audio', message.audio.file_id

                # ── Get direct Telegram CDN URL (fast loading, no proxy needed) ──
                if f_id:
                    try:
                        file_info = bot.get_file(f_id)
                        direct_url = f'https://api.telegram.org/file/bot{ADVERT_BOT_TOKEN}/{file_info.file_path}'
                    except Exception as e:
                        print(f'⚠️ Could not get direct URL: {e}')

                title = message.caption or message.text or "School Update"
                msg_id = message.message_id

                content.insert(0, {
                    "type": type_str,
                    "file_id": f_id,
                    "direct_url": direct_url,
                    "title": title,
                    "message_id": msg_id,
                    "date": datetime.now().isoformat()
                })
                write_json(DATA_FILE, content[:100])

                # ── Permanent Delete button attached to every post ──
                markup = types.InlineKeyboardMarkup()
                markup.row(
                    types.InlineKeyboardButton(
                        "🗑️ Delete from Website",
                        callback_data=f"del_{msg_id}"
                    )
                )

                bot.reply_to(message,
                    f"✅ *Saved to website!*\n"
                    f"📌 Type: {type_str.upper()}\n"
                    f"📝 Title: {title[:60]}\n"
                    f"📊 Total posts: {len(content)}\n\n"
                    f"⬇️ Press the button below to delete anytime:",
                    parse_mode='Markdown',
                    reply_markup=markup
                )
                print(f"🎬 Advert Saved: {type_str} — '{title[:40]}'")

            # ── Handle Delete button press ──
            @bot.callback_query_handler(func=lambda call: call.data.startswith('del_'))
            def handle_delete_callback(call):
                if str(call.from_user.id) != DIRECTOR_CHAT_ID:
                    bot.answer_callback_query(call.id, "⛔ Access denied.")
                    return

                try:
                    msg_id = int(call.data.replace('del_', ''))
                    content = read_json(DATA_FILE)
                    original_len = len(content)
                    content = [c for c in content if c.get('message_id') != msg_id]

                    if len(content) < original_len:
                        write_json(DATA_FILE, content)
                        # Update button to show it was deleted
                        markup = types.InlineKeyboardMarkup()
                        markup.row(
                            types.InlineKeyboardButton("✅ Deleted from Website", callback_data="done")
                        )
                        bot.edit_message_reply_markup(
                            chat_id=call.message.chat.id,
                            message_id=call.message.message_id,
                            reply_markup=markup
                        )
                        bot.answer_callback_query(call.id, "✅ Deleted from website!")
                        print(f"🗑️ Deleted via button: message_id={msg_id}")
                    else:
                        bot.answer_callback_query(call.id, "⚠️ Already deleted or not found.")
                except Exception as e:
                    bot.answer_callback_query(call.id, f"❌ Error: {str(e)[:50]}")

            @bot.callback_query_handler(func=lambda call: call.data == 'done')
            def handle_done_callback(call):
                bot.answer_callback_query(call.id, "Already deleted ✅")

            print("🎬 Advert Bot Started")
            bot.infinity_polling(timeout=30, long_polling_timeout=30)

        except Exception as e:
            err_str = str(e)
            if '409' in err_str:
                print(f"⚠️ Advert Bot: 409 conflict. Retrying in 20s...")
                time.sleep(20)
            else:
                print(f"⚠️ Advert Bot crashed, restarting in 5s: {e}")
                time.sleep(5)

# ─────────────────────────────────────────────────────────────
#  SCHOOL BOT — Search registrations by name/phone/ID
# ─────────────────────────────────────────────────────────────
def run_school_bot_loop():
    while True:
        try:
            bot = telebot.TeleBot(SCHOOL_BOT_TOKEN)
            bot.remove_webhook()
            time.sleep(2)

            @bot.message_handler(commands=['start'])
            def school_start(message):
                bot.reply_to(message,
                    "🏫 *Birbirsa School Bot*\n\n"
                    "🔍 Type a student name, phone number, or ID to search.\n\n"
                    "Example: `Abebe` or `0912345678`",
                    parse_mode='Markdown'
                )

            @bot.message_handler(func=lambda m: True)
            def handle_school_search(message):
                if not message.text:
                    bot.reply_to(message, "Please send a text message to search.")
                    return

                query = message.text.strip()
                if query.startswith('/'):
                    return  # ignore unknown commands

                regs = read_json(REG_FILE)
                q    = query.lower()
                print(f"🔍 Bot search '{q}' in {len(regs)} records")

                results = [r for r in regs if (
                    q in r.get('name', '').lower() or
                    q in r.get('phone', '') or
                    q in r.get('reg_id', '').lower() or
                    q in r.get('details', '').lower()
                )]

                if not results:
                    bot.send_message(message.chat.id,
                        f"❌ No records found for *'{query}'*\n\n"
                        f"📊 Total students in database: {len(regs)}",
                        parse_mode='Markdown'
                    )
                    return

                bot.send_message(message.chat.id, f"🔍 Found *{len(results)}* record(s):", parse_mode='Markdown')

                for r in results[:5]:
                    phone       = r.get('phone', '')
                    clean_phone = re.sub(r'[^0-9+]', '', phone)

                    msg  = f"👤 *Name:* {r.get('name', 'N/A')}\n"
                    msg += f"📞 *Phone:* {phone}\n"
                    msg += f"🆔 *ID:* {r.get('reg_id', 'N/A')}\n"
                    msg += f"🎓 *Details:* {r.get('details', 'N/A')}"

                    markup = types.InlineKeyboardMarkup()
                    if clean_phone:
                        markup.row(
                            types.InlineKeyboardButton("📞 Call", url=f"https://wa.me/{clean_phone}"),
                            types.InlineKeyboardButton("💬 Copy Phone", url=f"https://t.me/share/url?url={clean_phone}&text=Phone+number")
                        )

                    bot.send_message(message.chat.id, msg, parse_mode='Markdown', reply_markup=markup)

            print("🔍 School Bot Started")
            bot.infinity_polling(timeout=30, long_polling_timeout=30)

        except Exception as e:
            err_str = str(e)
            if '409' in err_str:
                print(f"⚠️ School Bot: 409 conflict. Retrying in 20s...")
                time.sleep(20)
            else:
                print(f"⚠️ School Bot crashed, restarting in 5s: {e}")
                time.sleep(5)

# ─────────────────────────────────────────────────────────────
#  LAUNCH — Start bots only ONCE (safe for gunicorn multi-worker)
# ─────────────────────────────────────────────────────────────
_BOT_LOCK_FILE = os.path.join(DATA_DIR, '.bot_lock')

def _start_bots_once():
    global _bots_started
    if _bots_started:
        return

    if fcntl is not None:
        # Linux/Mac (Render): use file lock so only ONE gunicorn worker runs bots
        try:
            lock_fd = open(_BOT_LOCK_FILE, 'w')
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (IOError, OSError):
            print('⚡ Bot threads already running in another worker. Skipping.')
            return

    _bots_started = True
    threading.Thread(target=run_advert_bot_loop, daemon=True).start()
    threading.Thread(target=run_school_bot_loop, daemon=True).start()
    print('🤖 Bot threads started (advert + school)')

# ─────────────────────────────────────────────────────────────
#  KEEP-ALIVE — Prevent Render free tier from sleeping
#  Pings own /health every 10 minutes using RENDER_EXTERNAL_URL
# ─────────────────────────────────────────────────────────────
def _keep_alive():
    render_url = os.environ.get('RENDER_EXTERNAL_URL', '').rstrip('/')
    if not render_url:
        print('ℹ️ RENDER_EXTERNAL_URL not set — keep-alive disabled')
        return
    print(f'💓 Keep-alive started → pinging {render_url}/health every 10 min')
    time.sleep(30)  # Wait for server to fully start
    while True:
        try:
            resp = requests.get(f'{render_url}/health', timeout=15)
            print(f'💓 Keep-alive ping OK ({resp.status_code})')
        except Exception as e:
            print(f'⚠️ Keep-alive ping failed: {e}')
        time.sleep(600)  # Every 10 minutes

_start_bots_once()
threading.Thread(target=_keep_alive, daemon=True).start()

if __name__ == '__main__':
    print(f'🚀 SYSTEM ONLINE: Running on Port {PORT}')
    app.run(host='0.0.0.0', port=PORT)
