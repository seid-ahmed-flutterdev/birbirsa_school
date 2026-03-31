import telebot
from telebot import types
import json
import os
import re
import threading
import time
import requests
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ─────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────
REG_BOT_TOKEN    = '8363076420:AAEZ78VfLhgjLBFlzAEjvqf1jt10A30TPGU'
DIRECTOR_CHAT_ID = '8319751158'
VERSION          = "8.0 (Save Button)"
SAVE_API_PORT    = 3001   # Built-in HTTP server port for saving registrations

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE   = os.path.join(BACKEND_DIR, 'registrations.json')
MEDIA_DIR   = os.path.join(BACKEND_DIR, 'media')

print(f"🚀 Starting Birbirsa School Bot v{VERSION}...")
os.makedirs(MEDIA_DIR, exist_ok=True)
if not os.path.exists(DATA_FILE):
    with open(DATA_FILE, 'w') as f:
        json.dump([], f)

# ─────────────────────────────────────────────
#  DATA HELPERS
# ─────────────────────────────────────────────
_db_lock = threading.Lock()

def read_registrations():
    with _db_lock:
        try:
            with open(DATA_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return []

def save_registrations(data):
    with _db_lock:
        with open(DATA_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

# ─────────────────────────────────────────────
#  TEXT EXTRACTION
# ─────────────────────────────────────────────
def extract_info(text):
    if not text:
        return {'name': '', 'phone': '', 'grade': '', 'section': '', 'id': '', 'stream': '', 'father': '', 'mother': ''}
    res = {'name': '', 'phone': '', 'grade': '', 'section': '', 'id': '', 'stream': '', 'father': '', 'mother': ''}
    for line in text.split('\n'):
        stripped = re.sub(r'^[^\x00-\x7F]+\s*', '', line).strip()
        lower = stripped.lower()
        if re.match(r'(student|name)\s*:', lower) and not res['name']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['name'] = val
        elif re.match(r'phone\s*:', lower) and not res['phone']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['phone'] = val
        elif re.match(r'grade\s*:', lower) and not res['grade']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['grade'] = val
        elif re.match(r'section\s*:', lower) and not res['section']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['section'] = val
        elif re.match(r'(stream|science stream)\s*:', lower) and not res['stream']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['stream'] = val
        elif re.match(r'(father|father.s name)\s*:', lower) and not res['father']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['father'] = val
        elif re.match(r'(mother|mother.s name)\s*:', lower) and not res['mother']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['mother'] = val
        elif re.match(r'id\s*:', lower) and not res['id']:
            val = stripped.split(':', 1)[-1].strip()
            if val: res['id'] = val
    # Fallback regexes
    if not res['name']:
        m = re.search(r'(?:student|name)\s*:\s*(.+)', text, re.IGNORECASE)
        if m: res['name'] = m.group(1).strip()
    if not res['phone']:
        m = re.search(r'phone\s*:\s*(.+)', text, re.IGNORECASE)
        if m: res['phone'] = m.group(1).strip()
    return res

# ─────────────────────────────────────────────
#  PENDING SAVE ENTRIES (for Save Button)
#  key = callback_data string, value = dict with info to save
# ─────────────────────────────────────────────
_pending_saves = {}
_pending_lock  = threading.Lock()

def store_pending(key, entry):
    with _pending_lock:
        _pending_saves[key] = entry

def pop_pending(key):
    with _pending_lock:
        return _pending_saves.pop(key, None)

# ─────────────────────────────────────────────
#  CORE SAVE LOGIC
# ─────────────────────────────────────────────
def save_record(name, phone, reg_id, details, rtype, img_path=None):
    """Save a registration/payment record. Returns True if new, False if duplicate."""
    regs = read_registrations()
    # Duplicate check by registration ID (most reliable)
    if reg_id:
        already = any(reg_id.lower() in r.get('details','').lower() for r in regs)
    else:
        already = any(
            r.get('name','').strip().lower() == name.lower() and
            r.get('phone','').strip() == phone
            for r in regs
        )
    if not already:
        regs.append({
            'name': name, 'phone': phone, 'type': rtype,
            'details': details, 'photo': img_path,
            'date': datetime.now().isoformat(),
        })
        save_registrations(regs)
        print(f"✅ SAVED [{rtype}]: {name} / {phone} / ID: {reg_id}")
        return True
    print(f"ℹ️ Already in DB: {name} / {reg_id}")
    return False

# ─────────────────────────────────────────────
#  BUILT-IN HTTP SERVER (port 3001)
#  Flutter calls this to save registrations directly
# ─────────────────────────────────────────────
class RegistrationHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress HTTP logs

    def _cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS, GET')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/health':
            body = json.dumps({'status': 'ok', 'version': VERSION,
                               'records': len(read_registrations())}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._cors_headers()
            self.end_headers()
            self.wfile.write(body)
        elif parsed.path == '/api/registrations':
            regs = read_registrations()
            body = json.dumps(regs, ensure_ascii=False).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._cors_headers()
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            body   = self.rfile.read(length)
            data   = json.loads(body.decode('utf-8'))
        except Exception as e:
            print(f"❌ HTTP parse error: {e}")
            self.send_response(400)
            self._cors_headers()
            self.end_headers()
            return

        # ── /api/store-pending: server.py deposits registration data here ──
        if self.path == '/api/store-pending':
            key      = (data.get('key') or '').strip()
            name     = (data.get('name') or '').strip()
            phone    = (data.get('phone') or '').strip()
            reg_id   = (data.get('reg_id') or '').strip()
            details  = (data.get('details') or '').strip()
            rtype    = (data.get('rtype') or 'registration').strip()
            file_ids = data.get('file_ids') or []
            if key and name:
                store_pending(key, {
                    'name':     name,
                    'phone':    phone,
                    'reg_id':   reg_id,
                    'details':  details,
                    'rtype':    rtype,
                    'img_path': data.get('img_path'),   # ← disk path of photos
                    'file_ids': file_ids,
                    'chat_id':  int(DIRECTOR_CHAT_ID),
                })
                print(f"📥 Stored pending [{key}]: {name}")
                resp = json.dumps({'ok': True}).encode()
                self.send_response(200)
            else:
                resp = json.dumps({'error': 'Missing key or name'}).encode()
                self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self._cors_headers()
            self.end_headers()
            self.wfile.write(resp)
            return

        # ── /api/save-registration: legacy direct save ──
        if self.path == '/api/save-registration':
            name    = (data.get('name') or '').strip()
            phone   = (data.get('phone') or '').strip()
            reg_id  = (data.get('reg_id') or '').strip()
            details = (data.get('details') or '').strip()
            rtype   = (data.get('type') or 'registration').strip()

            if not name:
                resp = json.dumps({'error': 'Missing name'}).encode()
                self.send_response(400)
            else:
                saved = save_record(name, phone, reg_id, details, rtype)
                total = len(read_registrations())
                resp  = json.dumps({'success': True, 'saved': saved, 'total': total}).encode()
                self.send_response(200)

            self.send_header('Content-Type', 'application/json')
            self._cors_headers()
            self.end_headers()
            self.wfile.write(resp)
            return

        # Unknown path
        self.send_response(404)
        self._cors_headers()
        self.end_headers()

def start_http_server():
    """Start the built-in HTTP server on port 3001."""
    server = HTTPServer(('0.0.0.0', SAVE_API_PORT), RegistrationHandler)
    print(f"🌐 Built-in save API running on port {SAVE_API_PORT}")
    server.serve_forever()

# ─────────────────────────────────────────────
#  BOT INIT
# ─────────────────────────────────────────────
bot = telebot.TeleBot(REG_BOT_TOKEN, parse_mode=None)
print(f"✅ Bot ready: v{VERSION}")

# ─────────────────────────────────────────────
#  IMAGE SAVING
# ─────────────────────────────────────────────
def save_images_from_file_ids(file_ids, student_name):
    if not file_ids:
        return None
    safe_name = re.sub(r'[^\w\s\-]', '', student_name).strip() or 'unknown'
    ts = int(datetime.now().timestamp())
    saved = []
    for idx, fid in enumerate(file_ids):
        try:
            info = bot.get_file(fid)
            data = bot.download_file(info.file_path)
            ext  = os.path.splitext(info.file_path)[1] or '.jpg'
            fname = f"{safe_name}_{ts}_{idx}{ext}"
            with open(os.path.join(MEDIA_DIR, fname), 'wb') as fp:
                fp.write(data)
            saved.append(fname)
        except Exception as e:
            print(f"  ⚠️ Could not save image {idx}: {e}")
    return ','.join(saved) if saved else None

# ─────────────────────────────────────────────
#  SEARCH HELPER
# ─────────────────────────────────────────────
def do_search(chat_id, query_raw):
    query = query_raw.lower().strip()
    if not query:
        bot.send_message(chat_id, "⚠️ Please type a student name or phone number.")
        return

    regs = read_registrations()

    def matches(r):
        if query in r.get('name', '').lower(): return True
        if query in r.get('phone', '').lower(): return True
        info = extract_info(r.get('details', ''))
        for field in ['name', 'grade', 'section', 'id', 'phone', 'father', 'mother', 'stream']:
            if query in info.get(field, '').lower(): return True
        details = r.get('details', '')
        if query in re.sub(r'[^\x00-\x7F]', '', details).lower(): return True
        if query in details.lower(): return True
        return False

    results = [r for r in regs if matches(r)]

    # ── FALLBACK: search via server.py port 3000 in case record was saved there ──
    if not results:
        try:
            resp = requests.get(
                f'http://localhost:3000/api/registrations/search',
                params={'q': query}, timeout=3
            )
            if resp.status_code == 200:
                data = resp.json()
                fallback = data.get('results', [])
                seen_ids = set()
                for r in regs:
                    d = r.get('details', '')
                    m = re.search(r'ID:\s*((?:BR|PAY)\d+)', d, re.IGNORECASE)
                    if m: seen_ids.add(m.group(1).lower())
                for r in fallback:
                    d = r.get('details', '')
                    m = re.search(r'ID:\s*((?:BR|PAY)\d+)', d, re.IGNORECASE)
                    rid = m.group(1).lower() if m else None
                    if rid and rid not in seen_ids:
                        results.append(r)
                        seen_ids.add(rid)
                    elif not rid:
                        results.append(r)
        except Exception as e:
            print(f"⚠️ Fallback search failed: {e}")

    if not results:
        bot.send_message(
            chat_id,
            f"❌ *Not found:* \"{query_raw}\"\n\n"
            f"Tips:\n"
            f"• Make sure the student was registered\n"
            f"• Try searching part of the name (e.g. first 3 letters)\n"
            f"• Or search by phone number\n\n"
            f"📊 Total records in database: *{len(regs)}*",
            parse_mode='Markdown'
        )
        return

    bot.send_message(chat_id, f"🔍 Found *{len(results)}* result(s):", parse_mode='Markdown')
    for r in results:
        _send_student_result(chat_id, r)

def _send_student_result(chat_id, r):
    """Send a single student search result. Photos + text ALWAYS together as ONE message."""
    import html as _html
    info     = extract_info(r.get('details', ''))
    rtype    = r.get('type', 'registration')
    badge    = '📝 REGISTRATION' if rtype == 'registration' else '💸 PAYMENT'
    date_str = r.get('date', '')[:10]

    def _e(txt): return _html.escape(str(txt)) if txt else '?'

    name  = r.get('name') or info.get('name') or '?'
    phone = r.get('phone') or info.get('phone') or '?'

    summary  = f"{'━'*24}\n<b>{_e(badge)}</b>\n{'━'*24}\n"
    summary += f"👤 <b>Name:</b> {_e(name)}\n📞 <b>Phone:</b> {_e(phone)}\n"
    if info.get('grade'):   summary += f"🎓 <b>Grade:</b> {_e(info['grade'])}\n"
    if info.get('section'): summary += f"📚 <b>Section:</b> {_e(info['section'])}\n"
    if info.get('stream'):  summary += f"🧬 <b>Stream:</b> {_e(info['stream'])}\n"
    if info.get('father'):  summary += f"👨 <b>Father:</b> {_e(info['father'])}\n"
    if info.get('mother'):  summary += f"👩 <b>Mother:</b> {_e(info['mother'])}\n"
    if info.get('id'):      summary += f"🆔 <b>ID:</b> {_e(info['id'])}\n"
    summary += f"📅 <b>Date:</b> {_e(date_str)}\n"

    # Plain-text version (fallback if HTML rejected by Telegram)
    plain = summary.replace('<b>', '').replace('</b>', '')

    # ── Collect ALL media files from disk ──
    all_files = []
    if r.get('photo'):
        for p in r['photo'].split(','):
            p = p.strip()
            if not p:
                continue
            fp = os.path.join(MEDIA_DIR, p)
            if os.path.exists(fp):
                all_files.append(fp)
            else:
                print(f"  ⚠️ Search result file missing: {fp}")

    # ── No media → send text only ──
    if not all_files:
        try:
            bot.send_message(chat_id, summary, parse_mode='HTML', reply_markup=keyboard)
        except Exception:
            try:
                bot.send_message(chat_id, plain, reply_markup=keyboard)
            except Exception as e:
                print(f"❌ Could not send search result text: {e}")
        return

    # ── Classify into images vs documents ──
    IMG_EXTS = {'jpg','jpeg','png','webp','gif','bmp','heic','heif','tiff','tif'}
    image_files = []
    doc_files   = []
    for fp in all_files:
        ext = fp.rsplit('.', 1)[-1].lower() if '.' in fp else ''
        if ext in IMG_EXTS:
            image_files.append(fp)
        else:
            doc_files.append(fp)

    caption_html  = summary[:1024]
    caption_plain = plain[:1024]
    sent_ok = False

    # Build Inline Keyboard for Deletion
    keyboard = types.InlineKeyboardMarkup()
    # Create a safe callback ID using phone or name
    del_key = f"del_{phone}"[:32] if phone and phone != '?' else f"del_nam_{name}"[:32]
    keyboard.add(types.InlineKeyboardButton('🗑️ Delete from Database', callback_data=del_key))

    # ── Send ALL images as photos WITH caption (TOGETHER!) ──
    if image_files:
        try:
            if len(image_files) == 1:
                with open(image_files[0], 'rb') as f:
                    bot.send_photo(chat_id, f, caption=caption_html, parse_mode='HTML', reply_markup=keyboard)
                sent_ok = True
            else:
                handles = []
                media   = []
                try:
                    for i, fp in enumerate(image_files):
                        fh = open(fp, 'rb')
                        handles.append(fh)
                        if i == 0:
                            media.append(types.InputMediaPhoto(fh, caption=caption_html, parse_mode='HTML'))
                        else:
                            media.append(types.InputMediaPhoto(fh))
                    bot.send_media_group(chat_id, media)
                    
                    # send delete button immediately after media group
                    bot.send_message(chat_id, "Tap below to delete this record:", reply_markup=keyboard)
                    sent_ok = True
                finally:
                    for fh in handles:
                        fh.close()
        except Exception as e1:
            print(f"  ⚠️ Photo+HTML failed: {e1}, trying plain caption...")
            # Retry with plain text caption (HTML might be the issue)
            try:
                if len(image_files) == 1:
                    with open(image_files[0], 'rb') as f:
                        bot.send_photo(chat_id, f, caption=caption_plain, reply_markup=keyboard)
                    sent_ok = True
                else:
                    handles = []
                    media   = []
                    try:
                        for i, fp in enumerate(image_files):
                            fh = open(fp, 'rb')
                            handles.append(fh)
                            if i == 0:
                                media.append(types.InputMediaPhoto(fh, caption=caption_plain))
                            else:
                                media.append(types.InputMediaPhoto(fh))
                        bot.send_media_group(chat_id, media)
                        bot.send_message(chat_id, "Tap below to delete this record:", reply_markup=keyboard)
                        sent_ok = True
                    finally:
                        for fh in handles:
                            fh.close()
            except Exception as e2:
                print(f"  ⚠️ Photo+plain also failed: {e2}")

    # ── Send documents (with caption only if no images were sent) ──
    if doc_files:
        try:
            doc_cap = caption_html if not sent_ok else ''
            if len(doc_files) == 1:
                with open(doc_files[0], 'rb') as f:
                    bot.send_document(chat_id, f, caption=doc_cap, parse_mode='HTML' if doc_cap else None, reply_markup=keyboard if not sent_ok else None)
                if not sent_ok:
                    sent_ok = True
            else:
                handles = []
                media   = []
                try:
                    for i, fp in enumerate(doc_files):
                        fh = open(fp, 'rb')
                        handles.append(fh)
                        if i == 0 and not sent_ok:
                            media.append(types.InputMediaDocument(fh, caption=caption_html, parse_mode='HTML'))
                        else:
                            media.append(types.InputMediaDocument(fh))
                    bot.send_media_group(chat_id, media)
                    if not sent_ok:
                        bot.send_message(chat_id, "Tap below to delete this record:", reply_markup=keyboard)
                        sent_ok = True
                finally:
                    for fh in handles:
                        fh.close()
        except Exception as e:
            print(f"  ⚠️ Could not send docs: {e}")

    # ── Final fallback: text-only if everything failed ──
    if not sent_ok:
        try:
            bot.send_message(chat_id, summary, parse_mode='HTML', reply_markup=keyboard)
        except Exception:
            try:
                bot.send_message(chat_id, plain, reply_markup=keyboard)
            except Exception as e:
                print(f"❌ Total failure sending search result: {e}")

# ─────────────────────────────────────────────
#  SHOW REGISTRATION WITH SAVE BUTTON
# ─────────────────────────────────────────────
def _show_with_save_button(chat_id, text, file_ids, msg):
    """Show registration/payment info with a 💾 SAVE button. Does NOT auto-save."""
    import html
    def _e(txt): return html.escape(str(txt)) if txt else ''

    upper  = text.upper()
    is_reg = 'NEW REGISTRATION' in upper
    is_pay = 'NEW FEE PAYMENT' in upper
    if not (is_reg or is_pay):
        return False

    info   = extract_info(text)
    name   = info['name']
    phone  = info['phone']
    rtype  = 'registration' if is_reg else 'payment'
    if not name:
        return False

    reg_id_m = re.search(r'ID:\s*((?:BR|PAY)\d+)', text, re.IGNORECASE)
    reg_id   = reg_id_m.group(1) if reg_id_m else ''

    emoji  = '📝' if is_reg else '💸'
    label  = 'NEW REGISTRATION' if is_reg else 'NEW FEE PAYMENT'

    # Download file IDs before saving, if present
    img_path = save_images_from_file_ids(file_ids, name) if file_ids else None
    
    # Auto-save immediately! No button needed.
    saved = save_record(name, phone, reg_id, text, rtype, img_path=img_path)

    # Build a clean summary card using secure HTML
    card  = f"{emoji} <b>{_e(label)}</b>\n{'━'*28}\n"
    card += f"👤 <b>Name:</b> {_e(name)}\n"
    card += f"📞 <b>Phone:</b> {_e(phone)}\n"
    if info.get('grade'):   card += f"🎓 <b>Grade:</b> {_e(info['grade'])}\n"
    if info.get('section'): card += f"📚 <b>Section:</b> {_e(info['section'])}\n"
    if info.get('stream'):  card += f"🧬 <b>Stream:</b> {_e(info['stream'])}\n"
    if info.get('father'):  card += f"👨 <b>Father:</b> {_e(info['father'])}\n"
    if info.get('mother'):  card += f"👩 <b>Mother:</b> {_e(info['mother'])}\n"
    if reg_id:              card += f"🆔 <b>ID:</b> {_e(reg_id)}\n"
    card += f"{'━'*28}\n"
    card += f"✅ <b>Auto-Saved successfully!</b>" if saved else f"ℹ️ <b>Already in Database.</b>"

    # Send the card (with or without photo) natively, tightly bound to the media!
    try:
        if file_ids:
            if len(file_ids) == 1:
                bot.send_photo(chat_id, file_ids[0], caption=card[:1000], parse_mode='HTML')
            else:
                media = []
                for i, fid in enumerate(file_ids):
                    if i == 0:
                        media.append(types.InputMediaPhoto(fid, caption=card[:1000], parse_mode='HTML'))
                    else:
                        media.append(types.InputMediaPhoto(fid))
                bot.send_media_group(chat_id, media)
        else:
            bot.send_message(chat_id, card, parse_mode='HTML')
    except Exception as e:
        print(f"⚠️ Could not send card natively: {e}")
        try:
            bot.send_message(chat_id, card, parse_mode='HTML')
        except Exception as e2:
            print(f"❌ Even fallback failed: {e2}")

    return True

# ─────────────────────────────────────────────
#  CALLBACK QUERY HANDLER (Save Button press)
# ─────────────────────────────────────────────
@bot.callback_query_handler(func=lambda call: call.data.startswith('save_'))
def handle_save_callback(call):
    save_key = call.data
    entry    = pop_pending(save_key)   # try in-memory first

    # ── Fallback: check the shared pending_saves.json file ──
    if entry is None:
        pending_file = os.path.join(BACKEND_DIR, 'pending_saves.json')
        try:
            with open(pending_file, 'r', encoding='utf-8') as pf:
                pending_store = json.load(pf)
            if save_key in pending_store:
                entry = pending_store.pop(save_key)
                # Write back (remove used entry)
                with open(pending_file, 'w', encoding='utf-8') as pf:
                    json.dump(pending_store, pf, ensure_ascii=False, indent=2)
                print(f"📂 Loaded pending from file: {save_key}")
        except Exception as e:
            print(f"⚠️ Could not read pending file: {e}")

    if entry is None:
        # Truly not found — may have been already saved
        try:
            bot.answer_callback_query(call.id, "⚠️ Already saved or session expired.", show_alert=True)
            bot.edit_message_reply_markup(
                call.message.chat.id, call.message.message_id,
                reply_markup=None
            )
        except Exception:
            pass
        return

    name     = entry['name']
    phone    = entry['phone']
    reg_id   = entry['reg_id']
    details  = entry['details']
    rtype    = entry['rtype']
    file_ids = entry.get('file_ids') or []
    img_path = entry.get('img_path')   # photos already saved on disk by server.py

    # Download any Telegram file_ids (from bot messages) — usually empty for web registrations
    downloaded = save_images_from_file_ids(file_ids, name) if file_ids else None
    # Merge: prefer server-saved img_path, fall back to bot-downloaded
    final_img  = img_path or downloaded

    # Save to database
    saved = save_record(name, phone, reg_id, details, rtype, final_img)

    emoji = '📝' if rtype == 'registration' else '💸'

    if saved:
        confirm = (
            f"✅ *SAVED SUCCESSFULLY!*\n\n"
            f"{emoji} *{name}*\n"
            f"📞 {phone}\n"
            f"🆔 {reg_id or 'N/A'}\n\n"
            f"📂 Total records: *{len(read_registrations())}*"
        )
    else:
        confirm = (
            f"ℹ️ *Already in Database*\n\n"
            f"{emoji} {name}\n"
            f"📞 {phone}\n"
            f"🆔 {reg_id or 'N/A'}"
        )

    try:
        bot.answer_callback_query(call.id, "✅ Saved!" if saved else "ℹ️ Already saved", show_alert=False)
        # Edit the original message to show confirmation and remove button
        bot.edit_message_text(
            confirm,
            call.message.chat.id,
            call.message.message_id,
            parse_mode='Markdown',
            reply_markup=None
        )
    except Exception as e:
        print(f"⚠️ Could not edit message: {e}")
        try:
            bot.send_message(call.message.chat.id, confirm, parse_mode='Markdown')
        except Exception:
            pass

# ─────────────────────────────────────────────
#  ALBUM (media_group) HANDLER FOR SAVE BUTTON
# ─────────────────────────────────────────────
pending_albums = {}

def _process_album(mg):
    entry = pending_albums.pop(mg, None)
    if entry and entry.get('text'):
        _show_with_save_button(entry['chat_id'], entry['text'], entry['file_ids'], entry['msg'])

# ─────────────────────────────────────────────
#  DELETE CALLBACK HANDLER (Search results delete button)
# ─────────────────────────────────────────────
@bot.callback_query_handler(func=lambda call: call.data.startswith('del_'))
def handle_delete_record_callback(call):
    del_key = call.data
    # e.g., 'del_0911...' or 'del_nam_John'
    regs = read_registrations()
    original_len = len(regs)
    
    if del_key.startswith('del_nam_'):
        name_seg = del_key[8:].lower()
        regs = [r for r in regs if r.get('name', '').lower() != name_seg]
    else:
        phone_seg = del_key[4:]
        regs = [r for r in regs if r.get('phone', '') != phone_seg]
        
    if len(regs) < original_len:
        save_registrations(regs)
        bot.answer_callback_query(call.id, "✅ Record deleted from database!", show_alert=True)
        try:
            bot.edit_message_reply_markup(chat_id=call.message.chat.id, message_id=call.message.message_id, reply_markup=None)
            bot.send_message(call.message.chat.id, "🗑️ Removed from database.")
        except:
            pass
    else:
        bot.answer_callback_query(call.id, "⚠️ Record not found or already deleted.", show_alert=True)

# ─────────────────────────────────────────────
#  COMMAND HANDLERS
# ─────────────────────────────────────────────
@bot.message_handler(commands=['start', 'help'])
def cmd_start(msg):
    bot.send_message(msg.chat.id,
        f"🎓 *Birbirsa School Bot* v{VERSION}\n\n"
        f"🔍 *SEARCH:* Just type a student name or phone\n"
        f"Example: `Abebe` or `/search Abebe`\n\n"
        f"💾 *SAVE:* When a registration arrives, press the\n"
        f"   [💾 SAVE TO DATABASE] button to save it.\n\n"
        f"📋 *COMMANDS:*\n"
        f"/search name — Search student\n"
        f"/list — Last 20 students\n"
        f"/count — Total records\n"
        f"/status — Bot status\n",
        parse_mode='Markdown')

@bot.message_handler(commands=['search'])
def cmd_search(msg):
    parts = msg.text.split(maxsplit=1)
    if len(parts) < 2 or not parts[1].strip():
        bot.reply_to(msg, "Usage: `/search student name`", parse_mode='Markdown')
        return
    do_search(msg.chat.id, parts[1].strip())

@bot.message_handler(commands=['list'])
def cmd_list(msg):
    regs = read_registrations()
    if not regs:
        bot.send_message(msg.chat.id, '📭 Database is empty.')
        return
    items = regs[-20:]
    lines = [f"{'📝' if r.get('type')=='registration' else '💸'} {r['name']} — {r.get('phone','?')} [{r.get('date','')[:10]}]"
             for r in reversed(items)]
    bot.send_message(msg.chat.id,
        f"📋 *Last {len(items)} Records:*\n\n" + '\n'.join(lines) +
        f"\n\n_Total: {len(regs)} records_", parse_mode='Markdown')

@bot.message_handler(commands=['count'])
def cmd_count(msg):
    regs = read_registrations()
    bot.send_message(msg.chat.id,
        f"📊 *Database:*\n"
        f"📝 Registrations: *{sum(1 for r in regs if r.get('type')=='registration')}*\n"
        f"💸 Payments: *{sum(1 for r in regs if r.get('type')=='payment')}*\n"
        f"📂 Total: *{len(regs)}*", parse_mode='Markdown')

@bot.message_handler(commands=['status', 'version'])
def cmd_status(msg):
    regs = read_registrations()
    bot.send_message(msg.chat.id,
        f"✅ *Birbirsa Bot STATUS*\n\n"
        f"🤖 Version: {VERSION}\n"
        f"⏰ Now: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"📂 Database: {len(regs)} records\n"
        f"🌐 Save API: port {SAVE_API_PORT} ✅\n"
        f"Bot is healthy! ✅", parse_mode='Markdown')

# ─────────────────────────────────────────────
#  GENERAL MESSAGE HANDLER
# ─────────────────────────────────────────────
@bot.message_handler(content_types=['text', 'photo', 'document'])
def handle_message(msg):
    chat_id = msg.chat.id
    text    = msg.text or msg.caption or ''

    # ── HANDLE ALBUM (multiple photos together) ──
    if msg.media_group_id:
        mg = msg.media_group_id
        if mg not in pending_albums:
            pending_albums[mg] = {'text':'','file_ids':[],'chat_id':chat_id,'msg':msg,'timer':None}
        if msg.photo:
            pending_albums[mg]['file_ids'].append(msg.photo[-1].file_id)
        if text and not pending_albums[mg]['text']:
            pending_albums[mg]['text'] = text
            pending_albums[mg]['msg']  = msg
        old = pending_albums[mg].get('timer')
        if old: old.cancel()
        t = threading.Timer(2.0, _process_album, args=[mg])
        t.daemon = True; t.start()
        pending_albums[mg]['timer'] = t
        return

    # ── SINGLE PHOTO ──
    if msg.photo:
        if text:
            _show_with_save_button(chat_id, text, [msg.photo[-1].file_id], msg)
        return

    if not text or text.startswith('/'):
        return

    upper = text.upper()
    if 'NEW REGISTRATION' in upper or 'NEW FEE PAYMENT' in upper:
        # Show info card with SAVE button — do NOT auto-save
        _show_with_save_button(chat_id, text, [], msg)
        return

    # Otherwise treat as a search query
    do_search(chat_id, text)

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────
if __name__ == '__main__':
    log_file = os.path.join(BACKEND_DIR, 'bot_errors.log')

    # Start built-in HTTP server for Flutter web saves
    http_thread = threading.Thread(target=start_http_server, daemon=True)
    http_thread.start()

    try:
        bot.send_message(
            DIRECTOR_CHAT_ID,
            f"🟢 *SYSTEM ONLINE — v{VERSION}*\n\n"
            f"✅ Save API: port {SAVE_API_PORT}\n"
            f"💾 Save Button: ENABLED\n"
            f"🔍 Search: type any name or phone\n"
            f"📂 Database: {len(read_registrations())} records",
            parse_mode='Markdown'
        )
    except Exception:
        pass

    while True:
        try:
            print("🔄 Polling started...")
            bot.infinity_polling(timeout=30, long_polling_timeout=20)
        except Exception as e:
            with open(log_file, 'a') as lf:
                lf.write(f"[{datetime.now()}] CRASH: {str(e)}\n")
            print(f"❌ BOT CRASHED: {e}. Restarting in 5s...")
            time.sleep(5)
