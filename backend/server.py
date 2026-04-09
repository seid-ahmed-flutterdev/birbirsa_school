import os
import json
import time
import mimetypes
import threading
import re
from datetime import datetime
from flask import Flask, request, jsonify, Response, stream_with_context, send_from_directory
from flask_cors import CORS
import telebot
from telebot import types
import requests
from urllib.parse import quote, urlparse

# ─────────────────────────────────────────────────────────────
#  CONFIG & PATHS
# ─────────────────────────────────────────────────────────────
BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE   = os.path.join(BACKEND_DIR, 'content.json')
REG_FILE    = os.path.join(BACKEND_DIR, 'registrations.json')
MEDIA_DIR   = os.path.join(BACKEND_DIR, 'media')
WEB_DIR     = os.path.realpath(os.path.join(BACKEND_DIR, '..', 'build', 'web'))

os.makedirs(MEDIA_DIR, exist_ok=True)

# CLOUD FIX: Use Port from environment variable (Railway/Render requirement)
PORT = int(os.environ.get('PORT', 3000))

# Bot Configurations
ADVERT_BOT_TOKEN = '8704157930:AAE8Q1Y_dKgIjPbdOBetsefPGAokNJLLoZo'  # Advert Bot
SCHOOL_BOT_TOKEN = '8363076420:AAEZ78VfLhgjLBFlzAEjvqf1jt10A30TPGU'  # School Bot
DIRECTOR_CHAT_ID = '8319751158'

# Ensure MIME types (critical for Flutter web)
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('application/json', '.json')
mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('text/css', '.css')

app = Flask(__name__, static_folder=WEB_DIR, static_url_path='')
CORS(app)

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

# ─────────────────────────────────────────────────────────────
#  DELETE CONTENT — removes advert items from content.json
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
#  MEDIA PROXY — streams Telegram files through the server
#  Fixes CORS issues when opening PDFs, images, videos
# ─────────────────────────────────────────────────────────────
@app.route('/api/proxy', methods=['GET', 'OPTIONS'])
def media_proxy():
    if request.method == 'OPTIONS':
        return Response('', 200, headers={'Access-Control-Allow-Origin': '*'})
    
    file_id = request.args.get('file_id')
    if not file_id: return "Missing file_id", 400
    
    # Try Advert Bot then School Bot for the file
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
    
    # PDF Direct Open Fix
    if '.pdf' in f_info.file_path.lower():
        out.headers['Content-Type'] = 'application/pdf'
        out.headers['Content-Disposition'] = 'inline'
    
    return out

# ─────────────────────────────────────────────────────────────
#  REGISTRATION / PAYMENT — handles BOTH JSON and multipart
#  PERMANENTLY FIXED:
#  1. Parses JSON when no files attached
#  2. Parses multipart form when files attached
#  3. SENDS PHOTOS to Telegram WITH the info message (together!)
#  4. Saves everything to registrations.json
# ─────────────────────────────────────────────────────────────
@app.route('/api/notify-registration', methods=['POST', 'OPTIONS'])
def web_registration_api():
    """Unified API for Registration/Payment uploads from Flutter Web"""
    if request.method == 'OPTIONS':
        return Response('', 200, headers={'Access-Control-Allow-Origin': '*',
                                           'Access-Control-Allow-Headers': 'Content-Type'})
    try:
        # ── PARSE INPUT: handle BOTH JSON and multipart form data ──
        if request.content_type and 'application/json' in request.content_type:
            # JSON body (no files)
            data = request.get_json(force=True) or {}
            name = data.get('name', 'Unknown')
            phone = data.get('phone', '')
            reg_id = data.get('reg_id', '')
            details = data.get('details', '')
            rtype = data.get('type', 'registration')
        else:
            # Multipart form data (with files)
            name = request.form.get('name', 'Unknown')
            phone = request.form.get('phone', '')
            reg_id = request.form.get('reg_id', '')
            details = request.form.get('details', '')
            rtype = request.form.get('type', 'registration')
        
        saved_files = []
        saved_paths = []
        # Save photos to disk
        if 'photos' in request.files:
            for f in request.files.getlist('photos'):
                fname = f"reg_{int(time.time())}_{f.filename}"
                fpath = os.path.join(MEDIA_DIR, fname)
                f.save(fpath)
                saved_files.append(fname)
                saved_paths.append(fpath)
        # Save docs to disk
        if 'docs' in request.files:
            for f in request.files.getlist('docs'):
                fname = f"doc_{int(time.time())}_{f.filename}"
                fpath = os.path.join(MEDIA_DIR, fname)
                f.save(fpath)
                saved_files.append(fname)
                saved_paths.append(fpath)
        
        # Add to local registrations database
        regs = read_json(REG_FILE)
        regs.insert(0, {
            "name": name, "phone": phone, "reg_id": reg_id,
            "details": details, "type": rtype, "photo": ",".join(saved_files),
            "date": datetime.now().isoformat()
        })
        write_json(REG_FILE, regs[:2000])
        print(f"✅ Registration saved: {name} ({rtype}) with {len(saved_files)} files")
        
        # ── NOTIFY DIRECTOR ON TELEGRAM ──
        # PERMANENT FIX: Send photos WITH the message (together!), not just text
        bot = telebot.TeleBot(SCHOOL_BOT_TOKEN)
        msg_text = f"🆕 *WEB SUBMISSION: {rtype.upper()}*\n\n👤 {name}\n📞 {phone}\n🆔 {reg_id}\n\n{details}"
        
        if saved_paths:
            # ── HAS FILES: Send first photo WITH caption (info + photo together) ──
            try:
                first_path = saved_paths[0]
                caption = msg_text[:1024]  # Telegram caption limit
                
                if first_path.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic')):
                    with open(first_path, 'rb') as photo:
                        bot.send_photo(DIRECTOR_CHAT_ID, photo, caption=caption, parse_mode='Markdown')
                else:
                    with open(first_path, 'rb') as doc:
                        bot.send_document(DIRECTOR_CHAT_ID, doc, caption=caption, parse_mode='Markdown')
                
                print(f"✅ Telegram: sent first file + caption together")
                
                # Send remaining files without caption
                for extra_path in saved_paths[1:]:
                    try:
                        if extra_path.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic')):
                            with open(extra_path, 'rb') as photo:
                                bot.send_photo(DIRECTOR_CHAT_ID, photo)
                        else:
                            with open(extra_path, 'rb') as doc:
                                bot.send_document(DIRECTOR_CHAT_ID, doc)
                        print(f"✅ Telegram: sent extra file")
                    except Exception as fe:
                        print(f"⚠️ Failed to send extra file: {fe}")
                        
            except Exception as te:
                # If photo send fails, fall back to text-only
                print(f"⚠️ Photo send failed, sending text only: {te}")
                bot.send_message(DIRECTOR_CHAT_ID, msg_text, parse_mode='Markdown')
        else:
            # ── NO FILES: Send text-only message ──
            bot.send_message(DIRECTOR_CHAT_ID, msg_text, parse_mode='Markdown')
            print(f"✅ Telegram: sent text-only notification")
        
        return jsonify({"success": True, "id": reg_id})
    except Exception as e:
        print(f"❌ Registration error: {e}")
        return jsonify({"error": str(e)}), 500

# ─────────────────────────────────────────────────────────────
#  TELEGRAM BOTS INTEGRATION
# ─────────────────────────────────────────────────────────────

def run_advert_bot_loop():
    """Advert Bot: Director sends media → saved to content.json → appears on website"""
    while True:
        try:
            bot = telebot.TeleBot(ADVERT_BOT_TOKEN)
            
            @bot.message_handler(content_types=['text', 'photo', 'video', 'document', 'audio'])
            def handle_advert_post(message):
                if str(message.chat.id) != DIRECTOR_CHAT_ID: return
                
                content = read_json(DATA_FILE)
                type_str = 'text'
                f_id = None
                if message.photo: type_str, f_id = 'image', message.photo[-1].file_id
                elif message.video: type_str, f_id = 'video', message.video.file_id
                elif message.document:
                    mime = message.document.mime_type or ''
                    type_str = 'pdf' if 'pdf' in mime else 'doc'
                    f_id = message.document.file_id
                elif message.audio: type_str, f_id = 'audio', message.audio.file_id
                    
                content.insert(0, {
                    "type": type_str, "file_id": f_id, 
                    "title": message.caption or message.text or "Update",
                    "message_id": message.message_id, "date": datetime.now().isoformat()
                })
                write_json(DATA_FILE, content[:100])
                bot.reply_to(message, f"✅ Saved to website! ({type_str})")
                print(f"🎬 Advert Saved: {type_str}")

            print("🎬 Advert Bot Started")
            bot.infinity_polling(timeout=30, long_polling_timeout=30)
        except Exception as e:
            print(f"⚠️ Advert Bot crashed, restarting in 5s: {e}")
            time.sleep(5)

def run_school_bot_loop():
    """School Bot: Search registrations by name/phone"""
    while True:
        try:
            bot = telebot.TeleBot(SCHOOL_BOT_TOKEN)
            
            @bot.message_handler(func=lambda m: True)
            def handle_school_search(message):
                query = message.text.lower().strip()
                regs = read_json(REG_FILE)
                results = [r for r in regs if query in r.get('name','').lower() or query in r.get('phone','')]
                
                if not results:
                    bot.send_message(message.chat.id, f"❌ No records found for '{query}'")
                    return
                    
                bot.send_message(message.chat.id, f"🔍 Found {len(results)} records:")
                for r in results[:5]:
                    msg = f"👤 {r['name']}\n📞 {r['phone']}\n📄 {r['details']}"
                    bot.send_message(message.chat.id, msg)

            print("🔍 School Bot Started")
            bot.infinity_polling(timeout=30, long_polling_timeout=30)
        except Exception as e:
            print(f"⚠️ School Bot crashed, restarting in 5s: {e}")
            time.sleep(5)

# ─────────────────────────────────────────────────────────────
#  LAUNCH PAD
# ─────────────────────────────────────────────────────────────
if __name__ == '__main__':
    # Start bot loops in background threads
    threading.Thread(target=run_advert_bot_loop, daemon=True).start()
    threading.Thread(target=run_school_bot_loop, daemon=True).start()
    
    print(f"🚀 SYSTEM ONLINE: Running on Port {PORT}")
    app.run(host='0.0.0.0', port=PORT)
