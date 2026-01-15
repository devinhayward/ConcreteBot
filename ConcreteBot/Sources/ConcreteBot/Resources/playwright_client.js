const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--prompt-file') {
      args.promptFile = argv[i + 1];
      i += 1;
    } else if (arg === '--pdf') {
      args.pdf = argv[i + 1];
      i += 1;
    } else if (arg === '--profile') {
      args.profile = argv[i + 1];
      i += 1;
    } else if (arg === '--headless') {
      args.headless = argv[i + 1] === 'true';
      i += 1;
    } else if (arg === '--channel') {
      args.channel = argv[i + 1];
      i += 1;
    } else if (arg === '--timeout') {
      args.timeout = Number(argv[i + 1]);
      i += 1;
    } else if (arg === '--manual-login') {
      args.manualLogin = true;
    }
  }
  return args;
}

async function waitForResponse(page, timeoutMs) {
  const stopButton = page.locator('button:has-text("Stop generating")');
  try {
    await stopButton.waitFor({ state: 'visible', timeout: timeoutMs });
    await stopButton.waitFor({ state: 'detached', timeout: timeoutMs });
  } catch (error) {
    // Continue even if the button isn't found; fallback to last message capture.
  }

  const messages = page.locator('[data-message-author-role="assistant"]');
  const count = await messages.count();
  if (count === 0) {
    throw new Error('No assistant response found.');
  }
  return messages.nth(count - 1).innerText();
}

async function attachPdf(page, pdfPath) {
  let fileInput = page.locator('input[type="file"]');
  let count = await fileInput.count();
  if (count === 0) {
    const attachButton = page.locator('button[aria-label="Attach files"], button[title="Attach files"]');
    if (await attachButton.count() > 0) {
      await attachButton.first().click();
    }
    fileInput = page.locator('input[type="file"]');
    count = await fileInput.count();
  }
  if (count === 0) {
    throw new Error('ChatGPT file input not found. Make sure file uploads are enabled.');
  }
  await fileInput.first().setInputFiles(pdfPath);
}

async function waitForComposer(page, timeoutMs) {
  const composerSelector = '[data-testid="prompt-textarea"], textarea';
  const loginSelector = 'input[type="email"], input[name="username"], button:has-text("Log in"), button:has-text("Sign in")';

  const result = await Promise.race([
    page.waitForSelector(composerSelector, { timeout: timeoutMs }).then(() => 'composer'),
    page.waitForSelector(loginSelector, { timeout: timeoutMs }).then(() => 'login'),
  ]).catch(() => null);

  if (result === 'login') {
    console.error('Login required. Complete login in the opened browser window.');
    await page.waitForSelector(composerSelector, { timeout: 300000 });
    return;
  }

  if (result !== 'composer') {
    throw new Error('Timed out waiting for ChatGPT composer. Are you logged in?');
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (!args.promptFile || !args.pdf || !args.profile) {
    throw new Error('Missing required arguments.');
  }

  const prompt = fs.readFileSync(args.promptFile, 'utf8');
  const pdfPath = path.resolve(args.pdf);

  const launchOptions = { headless: args.headless };
  if (args.channel) {
    launchOptions.channel = args.channel;
  }
  const context = await chromium.launchPersistentContext(args.profile, launchOptions);

  const page = context.pages()[0] || await context.newPage();
  await page.goto('https://chatgpt.com', { waitUntil: 'domcontentloaded' });

  if (args.manualLogin) {
    console.log('Complete login/challenge in the browser, then press Enter here to continue.');
    await new Promise((resolve) => process.stdin.once('data', resolve));
  }

  await waitForComposer(page, args.timeout || 60000);
  await attachPdf(page, pdfPath);

  const input = page.locator('[data-testid="prompt-textarea"], textarea').first();
  await input.fill(prompt);
  await input.press('Enter');

  const response = await waitForResponse(page, args.timeout || 120000);
  console.log(response.trim());

  await context.close();
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exit(1);
});
