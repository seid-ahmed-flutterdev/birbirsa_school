const TelegramBot = require('node-telegram-bot-api');
const fs = require('fs');
const path = require('path');

// Registration Bot Configuration
const REG_BOT_TOKEN = '8363076420:AAEZ78VfLhgjLBFlzAEjvqf1jt10A30TPGU';
const VERSION = "2.3 (Perfect Link - March 17)";
const bot = new TelegramBot(REG_BOT_TOKEN, { polling: true });

const DATA_FILE = path.join(__dirname, 'registrations.json');
const MEDIA_DIR = path.join(__dirname, 'media');

let recentPhotos = {}; // chatId: { fileId, time }

// Initialize directories
if (!fs.existsSync(MEDIA_DIR)) fs.mkdirSync(MEDIA_DIR);
if (!fs.existsSync(DATA_FILE)) fs.writeFileSync(DATA_FILE, JSON.stringify([]));

const readData = () => {
  try { return JSON.parse(fs.readFileSync(DATA_FILE)); }
  catch (e) { return []; }
};

const saveData = (data) => {
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
};

const extractInfo = (text) => {
  if (!text) return { name: '', phone: '', reg_id: '' };
  const res = { name: '', phone: '', reg_id: '' };
  const lines = text.split('\n');

  lines.forEach(line => {
    const clean = line.replace(/[^a-zA-Z0-9: ]/g, '').trim();
    const lower = clean.toLowerCase();

    if (lower.includes('student') || lower.includes('name')) {
      const val = clean.split(':').slice(-1)[0].trim().replace(/^(student|name)/i, '').trim();
      res.name = val;
    }
    if (lower.includes('phone')) {
      const val = clean.split(':').slice(-1)[0].trim().replace(/^(phone)/i, '').trim();
      res.phone = val;
    }
    if (lower.includes('id')) {
      const val = clean.split(':').slice(-1)[0].trim().replace(/^(id)/i, '').trim();
      res.reg_id = val;
    }
  });
  return res;
};

const saveImage = async (msg, studentName) => {
  try {
    let fileId = null;
    if (msg.photo) fileId = msg.photo[msg.photo.length - 1].file_id;
    else if (msg.reply_to_message && msg.reply_to_message.photo) fileId = msg.reply_to_message.photo[msg.reply_to_message.photo.length - 1].file_id;
    else if (recentPhotos[msg.chat.id] && (Date.now() - recentPhotos[msg.chat.id].time < 60000)) {
      fileId = recentPhotos[msg.chat.id].fileId;
    }

    if (!fileId) return null;

    const safeName = studentName.replace(/[^a-zA-Z0-9]/g, '_');
    const filename = `${safeName}_${Date.now()}.jpg`;
    const filePath = path.join(MEDIA_DIR, filename);

    const downloadPath = await bot.downloadFile(fileId, MEDIA_DIR);
    fs.renameSync(downloadPath, filePath);
    return filename;
  } catch (e) {
    console.error('❌ Image save failed:', e);
    return null;
  }
};

console.log(`🚀 Birbirsa Search Bot v${VERSION} Active...`);

bot.on('callback_query', async (query) => {
  if (query.data === 'btn_save_now') {
    const msg = query.message;
    const text = msg.text || msg.caption || '';
    const info = extractInfo(text);

    if (!info.name) {
      bot.answerCallbackQuery(query.id, { text: "❌ Error: Could not find name" });
      return;
    }

    const regs = readData();
    if (!regs.some(r => r.name.toLowerCase() === info.name.toLowerCase() && r.phone === info.phone)) {
      const photoPath = await saveImage(msg, info.name);
      regs.push({
        name: info.name,
        phone: info.phone,
        details: text,
        photo: photoPath,
        date: new Date().toISOString()
      });
      saveData(regs);
      bot.answerCallbackQuery(query.id, { text: `✅ Saved: ${info.name}` });
    } else {
      bot.answerCallbackQuery(query.id, { text: "Already exists!" });
    }

    const markup = { inline_keyboard: [[{ text: '✅ SAVED TO DATABASE', callback_data: 'already_saved' }]] };
    bot.editMessageReplyMarkup(markup, { chat_id: msg.chat.id, message_id: msg.message_id });
  }
});

bot.on('message', async (msg) => {
  const chatId = msg.chat.id;
  if (msg.photo) recentPhotos[chatId] = { fileId: msg.photo[msg.photo.length - 1].file_id, time: Date.now() };

  const text = msg.text || msg.caption || '';
  if (text.includes('NEW REGISTRATION') || text.includes('NEW FEE PAYMENT')) {
    const info = extractInfo(text);
    if (info.name) {
      const regs = readData();
      if (!regs.some(r => r.name.toLowerCase() === info.name.toLowerCase() && r.phone === info.phone)) {
        const photoPath = await saveImage(msg, info.name);
        regs.push({ name: info.name, phone: info.phone, details: text, photo: photoPath, date: new Date().toISOString() });
        saveData(regs);
        bot.sendMessage(chatId, `📦 Auto-recorded: ${info.name}`);
      }
    }
    return;
  }

  if (text === '/start') return bot.sendMessage(chatId, `🎓 Birbirsa Bot v${VERSION}\nSend name/phone to search.`);
  if (text === '/version') return bot.sendMessage(chatId, `🤖 Version: ${VERSION}`);

  if (!text.startsWith('/')) {
    const query = text.toLowerCase();
    const regs = readData();
    const results = regs.filter(r => r.name.toLowerCase().includes(query) || r.phone.includes(query));

    if (results.length === 0) return bot.sendMessage(chatId, `❓ No student found matching "${text}"`);

    for (const res of results) {
      if (res.photo && fs.existsSync(path.join(MEDIA_DIR, res.photo))) {
        await bot.sendPhoto(chatId, path.join(MEDIA_DIR, res.photo), { caption: res.details, parse_mode: 'Markdown' });
      } else {
        await bot.sendMessage(chatId, res.details, { parse_mode: 'Markdown' });
      }
    }
  }
});
