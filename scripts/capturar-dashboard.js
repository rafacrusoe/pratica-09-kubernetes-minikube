const fs = require('fs');
const { chromium } = require('playwright');

const output = process.argv[2];
const route = process.argv[3] || '#/workloads?namespace=default';
const tokenPath = process.env.DASHBOARD_TOKEN_FILE || '/tmp/dashboard-token';
const baseUrl = process.env.DASHBOARD_URL ||
  'http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/';

if (!output) {
  throw new Error('Informe o caminho do arquivo PNG.');
}

async function authenticate(page, token) {
  const tokenRadio = page.getByText(/^Token$/).first();
  if (await tokenRadio.isVisible().catch(() => false)) {
    await tokenRadio.click();
  }

  const textarea = page.locator('textarea').first();
  if (await textarea.isVisible().catch(() => false)) {
    await textarea.fill(token);
    const signIn = page.getByRole('button', { name: /sign in|entrar/i }).first();
    await signIn.click();
    await page.waitForTimeout(2500);
  }
}

(async () => {
  const token = fs.readFileSync(tokenPath, 'utf8').trim();
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1600, height: 1100 },
    ignoreHTTPSErrors: true,
    locale: 'pt-BR'
  });
  const page = await context.newPage();

  await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await authenticate(page, token);
  await page.goto(`${baseUrl}${route}`, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(9000);

  const content = await page.locator('body').innerText();
  if (/sign in|token|entrar/i.test(content) && !/workloads|pods|deployments|cargas de trabalho/i.test(content)) {
    await authenticate(page, token);
    await page.goto(`${baseUrl}${route}`, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForTimeout(7000);
  }

  fs.mkdirSync(require('path').dirname(output), { recursive: true });
  await page.screenshot({ path: output, fullPage: true });
  console.log(`Dashboard salvo em ${output}`);
  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
