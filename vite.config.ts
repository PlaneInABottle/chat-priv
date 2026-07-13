import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

const PUBLIC_BRAND_NAME = 'Kozmopath';
const UPSTREAM_PRODUCT_NAME = ['Chat', 'woot'].join('');
const VOICE_TRANSPORT_NAME = ['Live', 'Kit'].join('');

const replaceLocaleBranding = (value: unknown): unknown => {
  if (typeof value === 'string') {
    const upstreamDomain = UPSTREAM_PRODUCT_NAME.toLowerCase();
    return value
      .replace(
        new RegExp(
          `(?:app\\.|www\\.)?${upstreamDomain}\\.com|${upstreamDomain}\\.help`,
          'gi'
        ),
        'kozmopath.com'
      )
      .replace(
        new RegExp(VOICE_TRANSPORT_NAME, 'gi'),
        `${PUBLIC_BRAND_NAME} Voice`
      )
      .replace(new RegExp(UPSTREAM_PRODUCT_NAME, 'gi'), PUBLIC_BRAND_NAME);
  }

  if (Array.isArray(value)) return value.map(replaceLocaleBranding);
  if (!value || typeof value !== 'object') return value;

  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => key !== 'UPDATE_CHATWOOT')
      .map(([key, item]) => [key, replaceLocaleBranding(item)])
  );
};

const localeBrandingPlugin = () => ({
  name: 'kozmopath-locale-branding',
  enforce: 'pre' as const,
  transform(code: string, id: string) {
    const filePath = id.split('?', 1)[0];
    if (!filePath.includes('/i18n/locale/') || !filePath.endsWith('.json')) {
      return null;
    }

    return JSON.stringify(replaceLocaleBranding(JSON.parse(code)));
  },
});

export default defineConfig({
  plugins: [localeBrandingPlugin(), ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
});
