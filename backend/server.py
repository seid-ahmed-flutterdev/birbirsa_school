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

# CLOUD FIX: Use Port from environment variable (JustRunMy.App requirement)
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

@app.route('/api/notify-registration', methods=['POST'])
def web_registration_api():
    """Unified API for Registration/Payment uploads from Flutter Web"""
    try:
        # Handle both multipart and json
        name = request.form.get('name', 'Unknown')
        phone = request.form.get('phone', '')
        reg_id = request.form.get('reg_id', '')
        details = request.form.get('details', '')
        rtype = request.form.get('type', 'registration')
        
        saved_files = []
        # Save photos to disk
        if 'photos' in request.files:
            for f in request.files.getlist('photos'):
                fname = f"reg_{int(time.time())}_{f.filename}"
                f.save(os.path.join(MEDIA_DIR, fname))
                saved_files.append(fname)
        
        # Add to local registrations database
        regs = read_json(REG_FILE)
        regs.insert(0, {
            "name": name, "phone": phone, "reg_id": reg_id,
            "details": details, "type": rtype, "photo": ",".join(saved_files),
            "date": datetime.now().isoformat()
        })
        write_json(REG_FILE, regs[:2000])
        
        # Notify Director immediately
        msg = f"🆕 *WEB SUBMISSION: {rtype.upper()}*\n\n👤 {name}\n📞 {phone}\n🆔 {reg_id}\n\n{details}"
        telebot.TeleBot(SCHOOL_BOT_TOKEN).send_message(DIRECTOR_CHAT_ID, msg, parse_mode='Markdown')
        
        return jsonify({"success": True, "id": reg_id})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ─────────────────────────────────────────────────────────────
#  TELEGRAM BOTS INTEGRATION
# ─────────────────────────────────────────────────────────────

def run_advert_bot_loop():
    bot = telebot.TeleBot(ADVERT_BOT_TOKEN)
    
    @bot.message_handler(content_types=['text', 'photo', 'video', 'document'])
    def handle_advert_post(message):
        if str(message.chat.id) != DIRECTOR_CHAT_ID: return
        
        # Logic to save to content.json (Advert Bot functionality)
        content = read_json(DATA_FILE)
        type_str = 'text'
        f_id = None
        if message.photo: type_str, f_id = 'image', message.photo[-1].file_id
        elif message.video: type_str, f_id = 'video', message.video.file_id
        elif message.document:
            mime = message.document.mime_type or ''
            type_str = 'pdf' if 'pdf' in mime else 'doc'
            f_id = message.document.file_id
            
        content.insert(0, {
            "type": type_str, "file_id": f_id, 
            "title": message.caption or message.text or "Update",
            "message_id": message.message_id, "date": datetime.now().isoformat()
        })
        write_json(DATA_FILE, content[:100])
        print(f"🎬 Advert Saved: {type_str}")

    print("🎬 Advert Bot Started")
    bot.infinity_polling()

def run_school_bot_loop():
    bot = telebot.TeleBot(SCHOOL_BOT_TOKEN)
    
    @bot.message_handler(func=lambda m: True)
    def handle_school_search(message):
        # Full School Bot Search logic
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
    bot.infinity_polling()

# ─────────────────────────────────────────────────────────────
#  LAUNCH PAD
# ─────────────────────────────────────────────────────────────
if __name__ == '__main__':
    # Start bot loops in background threads
    threading.Thread(target=run_advert_bot_loop, daemon=True).start()
    threading.Thread(target=run_school_bot_loop, daemon=True).start()
    
    print(f"🚀 SYSTEM ONLINE: Running on Port {PORT}")
    app.run(host='0.0.0.0', port=PORT)
