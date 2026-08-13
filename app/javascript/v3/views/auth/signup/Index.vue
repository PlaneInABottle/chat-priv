<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import SignupForm from './components/Signup/Form.vue';

const store = useStore();
const globalConfig = computed(() => store.getters['globalConfig/get']);
const IKAS_WORDMARK_URL = '/marketing/assets/ikas-official-wordmark.svg';
const CONTROLLED_PRODUCT_URL =
  '/marketing/assets/pexels-2529148-gray-neon-sneakers.jpg';
</script>

<template>
  <main
    class="grid min-h-screen min-w-[320px] bg-[#fffdf7] text-[#10211f] lg:grid-cols-[minmax(500px,0.9fr)_minmax(600px,1.1fr)]"
  >
    <section
      data-testid="signup-form-plane"
      class="signup-form-plane order-1 flex min-h-screen flex-col bg-[#fffdf7] px-5 pb-8 pt-7 sm:px-10 lg:px-[clamp(55px,6vw,104px)] lg:pb-9 lg:pt-10"
      aria-labelledby="signup-title"
    >
      <router-link
        to="/"
        class="inline-flex w-max rounded-md focus-visible:outline focus-visible:outline-3 focus-visible:outline-offset-4 focus-visible:outline-[#6e8cff]"
        :aria-label="$t('REGISTER.FREEMIUM.BACK_HOME')"
      >
        <img
          :src="globalConfig.logo"
          :alt="globalConfig.installationName"
          class="block h-auto w-[10.625rem] lg:w-48"
        />
      </router-link>

      <div
        class="mx-auto mt-9 w-full max-w-[515px] lg:mt-[clamp(2.25rem,5.5vh,3.75rem)]"
      >
        <p class="mb-3 text-xs font-extrabold tracking-[0.13em] text-[#56645f]">
          {{ $t('REGISTER.FREEMIUM.EYEBROW') }}
        </p>
        <h1
          id="signup-title"
          class="m-0 max-w-[550px] font-[Georgia,'Times_New_Roman',serif] text-[clamp(2.6875rem,10vw,3.125rem)] font-normal leading-[0.98] tracking-[-0.055em] lg:text-[clamp(2.9375rem,4vw,3.8125rem)]"
        >
          {{ $t('REGISTER.FREEMIUM.TITLE') }}
        </h1>
        <p
          class="mt-5 max-w-[470px] text-base leading-relaxed text-[#52615c] lg:text-lg"
        >
          {{ $t('REGISTER.FREEMIUM.DESCRIPTION') }}
        </p>
        <div
          class="mt-5 flex items-center gap-3 rounded-2xl border border-[#10211f]/15 bg-[#f3f0e8] px-4 py-3"
        >
          <span
            aria-hidden="true"
            class="grid size-10 flex-none place-items-center rounded-full bg-[#d7ee72] font-[Georgia,serif] text-xl"
          >
            {{ $t('REGISTER.FREEMIUM.MONTHLY_CONVERSATIONS') }}
          </span>
          <p class="m-0 grid gap-0.5">
            <strong class="text-sm">{{
              $t('REGISTER.FREEMIUM.CONVERSATION_HEADLINE')
            }}</strong>
            <small class="text-sm leading-relaxed text-[#65726e]">{{
              $t('REGISTER.FREEMIUM.WORKSPACE_CREDITS')
            }}</small>
          </p>
        </div>
      </div>

      <div class="mx-auto mt-6 w-full max-w-[515px] lg:mt-6">
        <SignupForm />
        <p
          class="mb-0 mt-4 text-center text-sm font-bold text-[#34443f] lg:mt-4 lg:text-base"
        >
          {{ $t('REGISTER.HAVE_AN_ACCOUNT') }}{{ ' ' }}
          <router-link
            class="rounded-sm underline decoration-[#6e8cff] underline-offset-4 hover:text-[#304ebd] focus-visible:outline focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[#6e8cff]"
            to="/app/login"
          >
            {{ $t('LOGIN.SUBMIT') }}
          </router-link>
        </p>
      </div>
    </section>

    <aside
      data-testid="signup-proof-plane"
      class="relative order-2 flex min-h-[660px] flex-col overflow-hidden bg-[#10211f] px-5 py-9 text-[#f7f4eb] [isolation:isolate] sm:px-10 lg:min-h-screen lg:px-[clamp(55px,6vw,95px)] lg:py-10"
      aria-labelledby="signup-proof-title"
    >
      <div
        aria-hidden="true"
        class="absolute -right-[310px] -top-[210px] -z-10 size-[560px] rounded-full bg-[radial-gradient(circle,rgba(110,140,255,.74),rgba(255,107,74,.34)_50%,transparent_70%)] blur-xl"
      />
      <div
        aria-hidden="true"
        class="absolute -bottom-60 -left-64 -z-10 size-[430px] rounded-full bg-[radial-gradient(circle,rgba(215,238,114,.38),transparent_68%)] blur-xl"
      />

      <div class="mt-11 max-w-[560px] lg:mt-[clamp(2.5rem,6vh,3.75rem)]">
        <p class="mb-3 text-xs font-extrabold tracking-[0.13em] text-[#d7ee72]">
          {{ $t('REGISTER.FREEMIUM.PROOF_KICKER') }}
        </p>
        <h2
          id="signup-proof-title"
          class="m-0 font-[Georgia,'Times_New_Roman',serif] text-[42px] font-normal leading-none tracking-[-0.045em] lg:text-[clamp(38px,3.6vw,54px)]"
        >
          {{ $t('REGISTER.FREEMIUM.PROOF_TITLE') }}
        </h2>
        <p class="mt-4 max-w-[480px] text-sm leading-relaxed text-[#b2c0ba]">
          {{ $t('REGISTER.FREEMIUM.PROOF_DESCRIPTION') }}
        </p>
      </div>

      <ol
        class="mt-7 grid max-w-[640px] list-none grid-cols-1 p-0 sm:grid-cols-3 lg:mt-8"
        :aria-label="$t('REGISTER.FREEMIUM.SEQUENCE_LABEL')"
      >
        <li
          data-testid="freemium-sequence-step"
          class="relative min-h-20 border-l border-[#d7ee72]/35 py-3 pl-9 sm:min-h-24 sm:border-l-0 sm:border-t sm:px-4 sm:pb-4 sm:pt-5"
        >
          <span
            class="absolute left-2.5 top-2 text-xs text-[#7e8f88] sm:static"
          >
            {{ $t('REGISTER.FREEMIUM.SEQUENCE.ACCOUNT.NUMBER') }}
          </span>
          <div class="mt-1.5 grid gap-0.5 sm:mt-2">
            <strong class="text-sm">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ACCOUNT.TITLE')
            }}</strong>
            <small class="text-sm text-[#8fa098]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ACCOUNT.DETAIL')
            }}</small>
          </div>
        </li>
        <li
          data-testid="freemium-sequence-step"
          class="relative min-h-20 border-l border-[#d7ee72]/35 py-3 pl-9 sm:min-h-24 sm:border-l-0 sm:border-t sm:px-4 sm:pb-4 sm:pt-5"
        >
          <span
            class="absolute left-2.5 top-2 text-xs text-[#7e8f88] sm:static"
          >
            {{ $t('REGISTER.FREEMIUM.SEQUENCE.STORE.NUMBER') }}
          </span>
          <div class="mt-1.5 grid gap-0.5 sm:mt-2">
            <strong class="text-sm">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.STORE.TITLE')
            }}</strong>
            <small class="text-sm text-[#8fa098]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.STORE.DETAIL')
            }}</small>
          </div>
        </li>
        <li
          data-testid="freemium-sequence-step"
          class="relative min-h-20 border-l border-[#d7ee72]/35 py-3 pl-9 sm:min-h-24 sm:border-l-0 sm:border-t sm:px-4 sm:pb-4 sm:pt-5"
        >
          <span
            class="absolute left-2.5 top-2 text-xs text-[#7e8f88] sm:static"
          >
            {{ $t('REGISTER.FREEMIUM.SEQUENCE.ANSWER.NUMBER') }}
          </span>
          <div class="mt-1.5 grid gap-0.5 sm:mt-2">
            <strong class="text-sm">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ANSWER.TITLE')
            }}</strong>
            <small class="text-sm text-[#8fa098]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ANSWER.DETAIL')
            }}</small>
          </div>
        </li>
      </ol>

      <section
        class="mt-8 w-full max-w-[640px] overflow-hidden rounded-[22px] border border-white/15 bg-[#fffdf7] text-[#10211f] shadow-[0_28px_70px_rgba(0,0,0,.24)] lg:mt-auto"
        :aria-label="$t('REGISTER.FREEMIUM.CONVERSATION_LABEL')"
      >
        <div
          class="grid min-h-14 grid-cols-[2.125rem_1fr_auto] items-center gap-2 border-b border-[#10211f]/10 px-3.5"
        >
          <span
            class="grid size-[2.125rem] place-items-center rounded-full bg-[#dfe4ff] text-xs font-extrabold"
          >
            {{ $t('REGISTER.FREEMIUM.CONTACT_INITIALS') }}
          </span>
          <strong class="text-sm">{{
            $t('REGISTER.FREEMIUM.CONTACT_NAME')
          }}</strong>
          <img :src="IKAS_WORDMARK_URL" alt="ikas" class="h-auto w-20" />
        </div>
        <div class="grid gap-2 px-3.5 pb-1.5 pt-3.5 text-sm leading-relaxed">
          <p
            class="m-0 w-max max-w-[82%] justify-self-end rounded-[10px] bg-[#dfe4ff] px-3 py-2.5"
          >
            {{ $t('REGISTER.FREEMIUM.CUSTOMER_QUESTION') }}
          </p>
          <p
            class="m-0 grid w-max max-w-[82%] gap-0.5 rounded-[10px] border border-[#10211f]/10 bg-white px-3 py-2.5"
          >
            <strong class="text-xs uppercase tracking-[0.06em]">
              {{ $t('REGISTER.FREEMIUM.ASSISTANT_NAME') }}
            </strong>
            {{ $t('REGISTER.FREEMIUM.ASSISTANT_ANSWER') }}
          </p>
        </div>
        <div
          class="m-3.5 grid grid-cols-[4.75rem_1fr] items-center gap-3.5 rounded-[14px] border border-[#6e8cff]/25 bg-white p-2.5"
        >
          <img
            data-testid="controlled-product-image"
            :src="CONTROLLED_PRODUCT_URL"
            :alt="$t('REGISTER.FREEMIUM.PRODUCT_ALT')"
            class="size-[4.75rem] rounded-[10px] object-cover"
          />
          <div class="grid gap-1">
            <strong class="text-sm">{{
              $t('REGISTER.FREEMIUM.PRODUCT_TITLE')
            }}</strong>
            <span class="text-sm text-[#65726e]">{{
              $t('REGISTER.FREEMIUM.PRODUCT_SUMMARY')
            }}</span>
          </div>
        </div>
      </section>
    </aside>
  </main>
</template>

<style scoped>
/* The signup form plane is an intentionally fixed-light surface (cream #fffdf7).
   When the OS/browser root theme is dark, the shared next-color tokens flip
   (e.g. --slate-12 becomes near-white) and labels/inputs would drop to ~1.14:1
   contrast on this plane. Pin the verified light-token values locally so labels,
   inputs, placeholders and error text keep their design-system light contrast
   regardless of the root `.dark` theme. */
.signup-form-plane {
  --slate-6: 217 217 224;
  --slate-9: 139 141 152;
  --slate-10: 104 108 118;
  --slate-11: 74 79 88;
  --slate-12: 28 32 36;
  --teal-10: 13 155 138;
  --ruby-9: 229 70 102;
  --ruby-12: 100 23 43;
  --alpha-2: 196, 197, 198, 0.22;
  --black-alpha-2: 0, 0, 0, 0.04;
  --border-weak: 234 234 234;
}
</style>
