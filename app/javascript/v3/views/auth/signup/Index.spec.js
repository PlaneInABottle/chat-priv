import { shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import SignupIndex from './Index.vue';
import enSignup from 'dashboard/i18n/locale/en/signup.json';
import trSignup from 'dashboard/i18n/locale/tr/signup.json';

vi.mock('vuex');

describe('Signup Index', () => {
  beforeEach(() => {
    useStore.mockReturnValue({
      getters: {
        'globalConfig/get': {
          installationName: 'Kozmopath',
          logo: '/brand-assets/logo.svg',
          logoDark: '/brand-assets/logo_dark.svg',
        },
      },
    });
  });

  it('renders the selected form-first companion and product proof hierarchy', () => {
    const wrapper = shallowMount(SignupIndex, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          SignupForm: { template: '<form data-testid="signup-form" />' },
        },
      },
    });

    const formPlane = wrapper.get('[data-testid="signup-form-plane"]');
    const proofPlane = wrapper.get('[data-testid="signup-proof-plane"]');

    expect(formPlane.element.compareDocumentPosition(proofPlane.element)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
    expect(formPlane.text()).toContain('REGISTER.FREEMIUM.TITLE');
    expect(formPlane.text()).toContain(
      'REGISTER.FREEMIUM.CONVERSATION_HEADLINE'
    );
    expect(proofPlane.text()).toContain('REGISTER.FREEMIUM.PROOF_TITLE');
    expect(proofPlane.text()).not.toContain('REGISTER.FREEMIUM.REFERENCE');
    expect(
      proofPlane.findAll('[data-testid="freemium-sequence-step"]')
    ).toHaveLength(3);
    expect(wrapper.findAll('img[alt="Kozmopath"]')).toHaveLength(1);
    expect(formPlane.get('img[alt="Kozmopath"]')).toBeTruthy();
    expect(proofPlane.findAll('img[alt="Kozmopath"]')).toHaveLength(0);
    expect(proofPlane.get('img[alt="ikas"]').attributes('src')).toBe(
      '/marketing/assets/ikas-official-wordmark.svg'
    );
    expect(
      proofPlane
        .get('[data-testid="controlled-product-image"]')
        .attributes('src')
    ).toBe('/marketing/assets/pexels-2529148-gray-neon-sneakers.jpg');
    expect(wrapper.text()).not.toContain('prototype');
    expect(proofPlane.text()).not.toContain(
      'REGISTER.FREEMIUM.FIXTURE_DISCLOSURE'
    );
  });

  it('keeps the exact freemium English source strings without trial claims', () => {
    expect(enSignup.REGISTER.FREEMIUM.CONVERSATION_HEADLINE).toBe(
      '50 AI conversations every month.'
    );
    expect(enSignup.REGISTER.FREEMIUM.WORKSPACE_CREDITS).toBe(
      '600 AI credits per month.'
    );
    expect(JSON.stringify(enSignup.REGISTER.FREEMIUM)).not.toMatch(
      /trial|deneme|14 gün/
    );
  });

  it('uses the scaled rem typography contract for headline, description, logo and meta', () => {
    const wrapper = shallowMount(SignupIndex, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          SignupForm: { template: '<form data-testid="signup-form" />' },
        },
      },
    });

    const h1 = wrapper.get('#signup-title');
    expect(h1.classes()).toContain('text-[clamp(2.6875rem,10vw,3.125rem)]');
    expect(h1.classes()).toContain('lg:text-[clamp(2.9375rem,4vw,3.8125rem)]');
    // The headline type utilities must stay rem-based.
    expect(
      h1
        .classes()
        .filter(cls => cls.startsWith('text-['))
        .every(cls => !cls.includes('px'))
    ).toBe(true);

    const description = wrapper.get('#signup-title + p');
    expect(description.classes()).toContain('text-base');
    expect(description.classes()).toContain('lg:text-lg');

    const logo = wrapper.get('img[alt="Kozmopath"]');
    expect(logo.classes()).toContain('w-[10.625rem]');
    expect(logo.classes()).toContain('lg:w-48');

    expect(
      wrapper.get('[data-testid="freemium-sequence-step"] small').classes()
    ).toContain('text-sm');
    expect(
      wrapper
        .get('[data-testid="controlled-product-image"] + div > span')
        .classes()
    ).toContain('text-sm');

    expect(wrapper.get('p.text-center').classes()).toContain('lg:text-base');
  });

  it('keeps the balanced proof-plane composition contract (grid, sequence, conversation card)', () => {
    const wrapper = shallowMount(SignupIndex, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          SignupForm: { template: '<form data-testid="signup-form" />' },
        },
      },
    });

    expect(wrapper.get('main').classes()).toContain(
      'lg:grid-cols-[minmax(500px,0.9fr)_minmax(600px,1.1fr)]'
    );

    const step = wrapper.get('[data-testid="freemium-sequence-step"]');
    expect(step.classes()).toEqual(
      expect.arrayContaining(['min-h-20', 'sm:min-h-24'])
    );

    const conversation = wrapper
      .findAll('section')
      .find(
        section =>
          section.attributes('aria-label') ===
          'REGISTER.FREEMIUM.CONVERSATION_LABEL'
      );
    expect(conversation.classes()).toContain('max-w-[640px]');
    expect(conversation.get('img[alt="ikas"]').classes()).toContain('w-20');
    expect(
      conversation.get('[data-testid="controlled-product-image"]').classes()
    ).toContain('size-[4.75rem]');
    expect(conversation.get('span.rounded-full').classes()).toContain(
      'size-[2.125rem]'
    );
  });

  it('keeps the maintained signup locale structures aligned and Turkish presentation copy localized', () => {
    const flattenKeys = (value, prefix = '') =>
      Object.entries(value).flatMap(([key, nestedValue]) => {
        const fullKey = prefix ? `${prefix}.${key}` : key;
        return nestedValue && typeof nestedValue === 'object'
          ? flattenKeys(nestedValue, fullKey)
          : [fullKey];
      });

    expect(flattenKeys(trSignup)).toEqual(flattenKeys(enSignup));
    expect(JSON.stringify(trSignup.REGISTER)).not.toMatch(
      /Chatwoot|Woot server|Check your inbox|Enter your work email/
    );
  });

  it('compiles every maintained en/tr signup leaf with the vue-i18n message compiler', () => {
    const flattenLeaves = (value, prefix = '') =>
      Object.entries(value).flatMap(([key, nestedValue]) => {
        const fullKey = prefix ? `${prefix}.${key}` : key;
        return nestedValue && typeof nestedValue === 'object'
          ? flattenLeaves(nestedValue, fullKey)
          : [[fullKey, nestedValue]];
      });

    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const failures = [];
    try {
      [
        ['en', enSignup],
        ['tr', trSignup],
      ].forEach(([locale, messages]) => {
        const i18n = createI18n({
          legacy: false,
          locale,
          messages: { [locale]: messages },
          missingWarn: false,
          fallbackWarn: false,
        });
        flattenLeaves(messages).forEach(([keyPath]) => {
          const errorsBefore = errorSpy.mock.calls.length;
          try {
            // Same runtime compile path as production: compile errors are
            // thrown in production builds and logged as errors in dev/test.
            // Intentionally iterating locale JSON leaves in a regression spec.
            // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
            i18n.global.t(keyPath);
          } catch (error) {
            failures.push(`[${locale}] ${keyPath} threw: ${error.message}`);
            return;
          }
          const compileErrors = errorSpy.mock.calls
            .slice(errorsBefore)
            .filter(([message]) =>
              String(message).includes('Message compilation error')
            );
          if (compileErrors.length > 0) {
            failures.push(
              `[${locale}] ${keyPath} failed to compile: ${compileErrors[0]}`
            );
          }
        });
      });
    } finally {
      errorSpy.mockRestore();
    }
    expect(failures).toEqual([]);
  });

  it('renders the email placeholder as a literal @ in both maintained locales', () => {
    const renderPlaceholder = (locale, messages) =>
      createI18n({
        legacy: false,
        locale,
        messages: { [locale]: messages },
        missingWarn: false,
        fallbackWarn: false,
      }).global.t('REGISTER.EMAIL.PLACEHOLDER');

    expect(renderPlaceholder('en', enSignup)).toBe(
      'Enter your work email address. E.g., bruce@wayne.enterprises'
    );
    expect(renderPlaceholder('tr', trSignup)).toBe('Örn. destek@magazan.com');
  });
});
