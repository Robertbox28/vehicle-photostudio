// Server-Helfer in JavaScript:
//  - saveDataUri: speichert Screenshots im eigenen images/-Ordner (keine fremden Dateirechte nötig)
//  - discordPost: postet Embeds (optional mit Bild-Anhang) an einen Discord-Webhook,
//    mit Warteschlange und Rate-Limit-Behandlung
const fs = require('fs');
const path = require('path');
const https = require('https');
const { URL } = require('url');

const resPath = GetResourcePath(GetCurrentResourceName());
const imagesDir = path.resolve(resPath, 'images');

function parseDataUri(dataUri) {
    const m = /^data:([^;]+);base64,(.+)$/s.exec(dataUri || '');
    if (!m) return null;
    return { mime: m[1], data: Buffer.from(m[2], 'base64') };
}

exports('saveDataUri', (relPath, dataUri) => {
    try {
        const parsed = parseDataUri(dataUri);
        if (!parsed) return false;

        const target = path.resolve(resPath, relPath);
        if (!target.startsWith(imagesDir + path.sep)) return false; // nur in images/

        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, parsed.data);
        return true;
    } catch (e) {
        console.log(`[photostudio] Speichern fehlgeschlagen: ${e.message}`);
        return false;
    }
});

// ------------------------------------------------------------------
// Discord
// ------------------------------------------------------------------
const WEBHOOK_RE = /^https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/api\/webhooks\/\d+\/[\w-]+/;
const queue = [];
let pumping = false;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function send(job) {
    return new Promise((resolve) => {
        const boundary = '----vps' + Date.now().toString(16) + Math.random().toString(16).slice(2);
        const parts = [
            Buffer.from(
                `--${boundary}\r\nContent-Disposition: form-data; name="payload_json"\r\n` +
                `Content-Type: application/json\r\n\r\n${JSON.stringify(job.payload)}\r\n`
            ),
        ];
        if (job.file) {
            parts.push(Buffer.from(
                `--${boundary}\r\nContent-Disposition: form-data; name="files[0]"; filename="${job.file.name}"\r\n` +
                `Content-Type: ${job.file.mime}\r\n\r\n`
            ));
            parts.push(job.file.data);
            parts.push(Buffer.from('\r\n'));
        }
        parts.push(Buffer.from(`--${boundary}--\r\n`));
        const body = Buffer.concat(parts);

        const u = new URL(job.url);
        const req = https.request({
            hostname: u.hostname,
            path: u.pathname + u.search,
            method: 'POST',
            headers: {
                'Content-Type': `multipart/form-data; boundary=${boundary}`,
                'Content-Length': body.length,
            },
        }, (res) => {
            let data = '';
            res.on('data', (c) => (data += c));
            res.on('end', () => resolve({ status: res.statusCode, body: data }));
        });
        req.on('error', (e) => resolve({ status: 0, body: e.message }));
        req.setTimeout(20000, () => req.destroy(new Error('Timeout')));
        req.write(body);
        req.end();
    });
}

async function pump() {
    if (pumping) return;
    pumping = true;
    while (queue.length) {
        const job = queue[0];
        const res = await send(job);

        if (res.status === 429 && job.tries < 5) {
            job.tries++;
            let wait = 2000;
            try { wait = Math.ceil((JSON.parse(res.body).retry_after || 2) * 1000) + 250; } catch (_) {}
            await sleep(wait);
            continue;
        }

        queue.shift();
        if (res.status < 200 || res.status >= 300) {
            console.log(`[photostudio] Discord-Webhook Fehler (${res.status}): ${String(res.body).slice(0, 300)}`);
        }
        await sleep(1200); // Discord erlaubt ca. 5 Nachrichten pro 2 Sekunden
    }
    pumping = false;
}

// webhookUrl, payload (Tabelle), fileName (optional), dataUri (optional)
exports('discordPost', (webhookUrl, payload, fileName, dataUri) => {
    if (!WEBHOOK_RE.test(webhookUrl || '')) {
        console.log('[photostudio] Ungültige Discord-Webhook-URL – bitte die Convar prüfen.');
        return false;
    }
    let file = null;
    if (fileName && dataUri) {
        const parsed = parseDataUri(dataUri);
        if (parsed) file = { name: fileName, mime: parsed.mime, data: parsed.data };
    }
    queue.push({ url: webhookUrl, payload, file, tries: 0 });
    pump();
    return true;
});

// ------------------------------------------------------------------
// Galerie: lokale Bilder lesen / löschen (nur im eigenen images/-Ordner)
// ------------------------------------------------------------------
const MIME = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp' };

function safeImagePath(file) {
    if (typeof file !== 'string' || !/^[\w.-]+$/.test(file)) return null;
    const target = path.resolve(imagesDir, file);
    return target.startsWith(imagesDir + path.sep) ? target : null;
}

exports('readImageDataUri', (file) => {
    try {
        const target = safeImagePath(file);
        if (!target || !fs.existsSync(target)) return null;
        const ext = path.extname(target).slice(1).toLowerCase();
        if (!MIME[ext]) return null;
        return `data:${MIME[ext]};base64,${fs.readFileSync(target).toString('base64')}`;
    } catch (e) {
        return null;
    }
});

exports('deleteImage', (file) => {
    try {
        const target = safeImagePath(file);
        if (!target || !fs.existsSync(target)) return false;
        fs.unlinkSync(target);
        return true;
    } catch (e) {
        return false;
    }
});
