const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const TelegramBot = require('node-telegram-bot-api');
const axios = require('axios');

const app = express();
const PORT = 3000;
const DATA_FILE = path.join(__dirname, 'content.json');

// Bot Configuration
const BOT_TOKEN = '8704157930:AAE8Q1Y_dKgIjPbdOBetsefPGAokNJLLoZo'; // Advert Bot
const bot = new TelegramBot(BOT_TOKEN, { polling: true });

// Middleware
app.use(cors());
app.use(express.json());

// Set global CORS headers for all responses just in case
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, DELETE');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  next();
});

// Initialize data file if it doesn't exist
if (!fs.existsSync(DATA_FILE)) {
  fs.writeFileSync(DATA_FILE, JSON.stringify([]));
}

const readContent = () => {
  try { return JSON.parse(fs.readFileSync(DATA_FILE)); }
  catch (e) { return []; }
};

const writeContent = (content) => {
  fs.writeFileSync(DATA_FILE, JSON.stringify(content, null, 2));
};

// Filter messages to store into content.json
const handleMessage = async (msg) => {
  try {
    let type, file_id;
    let text = msg.text || msg.caption || '';
    const message_id = msg.message_id;
    const chat_id = msg.chat?.id;

    if (msg.photo) {
      type = 'image';
      file_id = msg.photo[msg.photo.length - 1].file_id;
    } else if (msg.video) {
      type = 'video';
      file_id = msg.video.file_id;
    } else if (msg.document) {
      const mime = msg.document.mime_type || '';
      if (mime.startsWith('image/')) type = 'image';
      else if (mime.startsWith('video/')) type = 'video';
      else if (mime === 'application/pdf') type = 'pdf';
      else type = 'doc';
      file_id = msg.document.file_id;
      if (!text) text = msg.document.file_name || 'Document';
    } else if (msg.audio || msg.voice) {
      type = 'audio';
      file_id = (msg.audio || msg.voice).file_id;
    } else if (msg.text) {
      if (msg.text.startsWith('/')) return; // Ignore commands
      type = 'text';
    }

    if (type) {
      const content = readContent();
      // Check if message_id already exists to prevent duplicates on edit
      const exists = content.some(item => item.message_id === message_id);

      if (!exists) {
        const emoji = type === 'image' ? '🖼️' : type === 'video' ? '🎬' : type === 'audio' ? '🎵' : type === 'pdf' ? '📄' : type === 'doc' ? '📎' : '📝';
        const newItem = {
          type,
          title: text || (type === 'text' ? 'Announcement' : 'Attachment'),
          file_id: file_id,
          message_id: message_id,
          chat_id: chat_id,
          date: new Date(msg.date * 1000).toISOString()
        };

        content.unshift(newItem);
        const saved = content.slice(0, 100);
        writeContent(saved);
        console.log(`✅ Saved ${type} as #1: ${newItem.title.substring(0, 30)}...`);

        // Notify director — each item gets its OWN delete button using message_id (permanent, never shifts)
        const totalItems = saved.length;
        const shortTitle = newItem.title.length > 40 ? newItem.title.substring(0, 40) + '…' : newItem.title;
        const notifyMsg =
          `✅ *Posted to website!*\n\n` +
          `${emoji} ${shortTitle}\n` +
          `📊 Type: ${type.toUpperCase()} · Total: ${totalItems}\n\n` +
          `_Tap the button below to delete this item:_`;

        const keyboard = {
          inline_keyboard: [[
            { text: `🗑️ Delete this`, callback_data: `del_${message_id}` }
          ]]
        };

        bot.sendMessage(chat_id, notifyMsg, { parse_mode: 'Markdown', reply_markup: keyboard }).catch(() => { });
      }
    }
  } catch (err) {
    console.error('❌ Msg error:', err.message);
  }
};

bot.on('message', handleMessage);
bot.on('channel_post', handleMessage);
bot.on('edited_message', handleMessage);
bot.on('edited_channel_post', handleMessage);

// ========== DIRECTOR COMMANDS ==========

const getEmoji = (type) => {
  if (type === 'image') return '🖼️';
  if (type === 'video') return '🎬';
  if (type === 'audio') return '🎵';
  if (type === 'pdf') return '📄';
  if (type === 'doc') return '📎';
  return '📝';
};

bot.onText(/\/list/, async (msg) => {
  const content = readContent();
  if (content.length === 0) {
    return bot.sendMessage(msg.chat.id, '📭 No content stored. Post something to the bot first.');
  }

  // Send a header message
  await bot.sendMessage(msg.chat.id, `📋 *Website Content* — ${content.length} item(s)\n_Tap 🗑️ Delete to remove from website:_`, { parse_mode: 'Markdown' });

  // Send each item as its own message with an inline Delete button
  for (let i = 0; i < content.length; i++) {
    const item = content[i];
    const emoji = getEmoji(item.type);
    const num = i + 1;
    const shortTitle = item.title.length > 50 ? item.title.substring(0, 50) + '…' : item.title;
    const dateStr = item.date ? new Date(item.date).toLocaleDateString('en-GB') : '?';

    const text =
      `*#${num}* ${emoji} ${shortTitle}\n` +
      `Type: ${item.type.toUpperCase()} · ${dateStr}`;

    const keyboard = {
      inline_keyboard: [[
        { text: `🗑️ Delete #${num}`, callback_data: `del_${item.message_id}` }
      ]]
    };

    await bot.sendMessage(msg.chat.id, text, {
      parse_mode: 'Markdown',
      reply_markup: keyboard
    });
  }
});

// Handle inline Delete button taps
bot.on('callback_query', async (query) => {
  const data = query.data;

  if (data && data.startsWith('del_')) {
    const messageId = parseInt(data.replace('del_', ''));
    const content = readContent();
    const index = content.findIndex(item => item.message_id === messageId);

    if (index !== -1) {
      const removed = content.splice(index, 1)[0];
      writeContent(content);
      const emoji = getEmoji(removed.type);
      console.log(`🗑️ Button deleted ${removed.type}: ${removed.title}`);

      // Update the button message to show it's deleted
      await bot.editMessageText(
        `✅ *Deleted from website*\n${emoji} ~~${removed.title.substring(0, 50)}~~`,
        {
          chat_id: query.message.chat.id,
          message_id: query.message.message_id,
          parse_mode: 'Markdown',
          reply_markup: { inline_keyboard: [] }
        }
      ).catch(() => { });

      await bot.answerCallbackQuery(query.id, { text: `✅ Deleted: ${removed.title.substring(0, 30)}` });
    } else {
      await bot.answerCallbackQuery(query.id, { text: '⚠️ Already deleted or not found.' });
    }
  }
});

bot.onText(/\/delete (\d+)/, (msg, match) => {
  const index = parseInt(match[1]) - 1;
  const content = readContent();
  if (index >= 0 && index < content.length) {
    const removed = content.splice(index, 1);
    writeContent(content);
    const emoji = getEmoji(removed[0].type);
    console.log(`🗑️ Bot deleted ${removed[0].type}: ${removed[0].title}`);
    bot.sendMessage(msg.chat.id, `✅ Deleted from website:\n${emoji} *${removed[0].title}*`, { parse_mode: 'Markdown' });
  } else {
    bot.sendMessage(msg.chat.id, `❌ Invalid number. Use /list to see items (1-${content.length}).`);
  }
});

bot.onText(/\/clear/, (msg) => {
  const count = readContent().length;
  writeContent([]);
  console.log(`🗑️ Bot cleared all ${count} items from website`);
  bot.sendMessage(msg.chat.id, `✅ Cleared all *${count}* items from the website.`, { parse_mode: 'Markdown' });
});

// ========== PROXY & API ==========

// Final Proxy Fix: Handles both bots, CORS, and inline PDF display
app.get('/api/proxy', async (req, res) => {
  try {
    const { file_id } = req.query;
    if (!file_id) return res.status(400).send('Missing file_id');

    console.log(`🖼️ Proxying file: ${file_id.substring(0, 10)}...`);
    const fileUrl = await getAnyFileLink(file_id);

    const axiosHeaders = { 'User-Agent': 'Mozilla/5.0' };
    if (req.headers.range) axiosHeaders['Range'] = req.headers.range;

    const response = await axios({
      method: 'get',
      url: fileUrl,
      responseType: 'stream',
      headers: axiosHeaders,
      validateStatus: (status) => status >= 200 && status < 400
    });

    res.status(response.status);

    const headersToForward = ['content-length', 'content-range', 'accept-ranges', 'cache-control'];
    headersToForward.forEach(h => {
      if (response.headers[h]) res.setHeader(h, response.headers[h]);
    });

    let contentType = response.headers['content-type'] || 'application/octet-stream';
    const lowUrl = fileUrl.toLowerCase();
    if (lowUrl.endsWith('.pdf')) contentType = 'application/pdf';
    else if (lowUrl.endsWith('.jpg') || lowUrl.endsWith('.jpeg')) contentType = 'image/jpeg';
    else if (lowUrl.endsWith('.png')) contentType = 'image/png';
    else if (lowUrl.endsWith('.mp4')) contentType = 'video/mp4';

    res.setHeader('Content-Type', contentType);
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');

    // FIX: Remove filename for PDFs to ensure browser opens them inline
    if (contentType === 'application/pdf') {
      res.setHeader('Content-Disposition', 'inline');
    } else {
      res.setHeader('Content-Disposition', 'inline; filename="preview"');
    }

    response.data.pipe(res);
  } catch (err) {
    console.error('❌ Proxy error:', err.message);
    res.status(404).send('Not found');
  }
});

app.get('/api/content', (req, res) => {
  const content = readContent();
  const origin = req.headers.host || 'localhost:3000';
  const protocol = req.headers['x-forwarded-proto'] || 'http';

  // Return content with dynamic proxy URLs
  const mapped = content.map(item => ({
    ...item,
    url: item.file_id ? `${protocol}://${origin}/api/proxy?file_id=${encodeURIComponent(item.file_id)}` : null
  }));
  res.json(mapped);
});

// ========== DELETE API (called by Flutter app & web) ==========

// Delete by message_id (used by Flutter app)
app.post('/api/content/delete', (req, res) => {
  const { message_id } = req.body;
  if (!message_id) return res.status(400).json({ error: 'Missing message_id' });

  const content = readContent();
  const before = content.length;
  const filtered = content.filter(item => item.message_id !== parseInt(message_id));

  if (filtered.length === before) {
    return res.status(404).json({ error: 'Item not found' });
  }

  writeContent(filtered);
  const deleted = content.find(item => item.message_id === parseInt(message_id));
  console.log(`🗑️ API deleted message_id=${message_id}: ${deleted?.title || 'unknown'}`);
  res.json({ success: true, deleted: deleted });
});

// Delete by index (1-based, for compatibility)
app.delete('/api/content/:index', (req, res) => {
  const index = parseInt(req.params.index) - 1;
  const content = readContent();
  if (index >= 0 && index < content.length) {
    const removed = content.splice(index, 1);
    writeContent(content);
    console.log(`🗑️ API deleted index ${index + 1}: ${removed[0].title}`);
    res.json({ success: true, deleted: removed[0] });
  } else {
    res.status(404).json({ error: 'Invalid index' });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 School Server running at http://localhost:${PORT}`);
  console.log(`🤖 Bot is active and listening...`);
});
