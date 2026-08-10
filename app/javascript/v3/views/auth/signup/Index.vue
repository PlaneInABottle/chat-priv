<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import SignupForm from './components/Signup/Form.vue';

const store = useStore();
const globalConfig = computed(() => store.getters['globalConfig/get']);
const IKAS_WORDMARK_URL = '/marketing/assets/ikas-official-wordmark.svg';
const CONTROLLED_PRODUCT_URL =
  '/marketing/assets/pexels-6046230-black-sweater-crop.jpg';
</script>

<template>
  <main
    class="grid min-h-screen min-w-[320px] bg-[#fffdf7] text-[#10211f] lg:grid-cols-[minmax(520px,0.92fr)_minmax(620px,1.08fr)]"
  >
    <section
      data-testid="signup-form-plane"
      class="order-1 flex min-h-screen flex-col bg-[#fffdf7] px-5 pb-8 pt-7 sm:px-10 lg:px-[clamp(55px,6vw,104px)] lg:pb-9 lg:pt-10"
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
          class="block h-auto w-[170px]"
        />
      </router-link>

      <div
        class="mx-auto mt-9 w-full max-w-[515px] lg:mt-[clamp(46px,7vh,72px)]"
      >
        <p
          class="mb-3 text-[11px] font-extrabold tracking-[0.13em] text-[#56645f]"
        >
          {{ $t('REGISTER.FREEMIUM.EYEBROW') }}
        </p>
        <h1
          id="signup-title"
          class="m-0 max-w-[550px] font-[Georgia,'Times_New_Roman',serif] text-[43px] font-normal leading-[0.98] tracking-[-0.055em] sm:text-[50px] lg:text-[clamp(47px,4vw,61px)]"
        >
          {{ $t('REGISTER.FREEMIUM.TITLE') }}
        </h1>
        <p
          class="mt-5 max-w-[470px] text-[15px] leading-relaxed text-[#52615c] lg:text-base"
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
            <strong class="text-xs">{{
              $t('REGISTER.FREEMIUM.CONVERSATION_HEADLINE')
            }}</strong>
            <small class="text-[11px] leading-relaxed text-[#65726e]">{{
              $t('REGISTER.FREEMIUM.WORKSPACE_CREDITS')
            }}</small>
          </p>
        </div>
      </div>

      <div class="mx-auto mt-6 w-full max-w-[515px]">
        <SignupForm />
        <p class="mb-0 mt-4 text-center text-xs font-bold text-[#34443f]">
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

      <div class="flex items-center justify-between">
        <img
          :src="globalConfig.logoDark || globalConfig.logo"
          :alt="globalConfig.installationName"
          class="h-auto w-[170px]"
        />
        <span class="font-mono text-[9px] tracking-[0.14em] text-[#84938d]">
          {{ $t('REGISTER.FREEMIUM.REFERENCE') }}
        </span>
      </div>

      <div class="mt-11 max-w-[520px] lg:mt-[clamp(45px,7vh,70px)]">
        <p
          class="mb-3 text-[10px] font-extrabold tracking-[0.13em] text-[#d7ee72]"
        >
          {{ $t('REGISTER.FREEMIUM.PROOF_KICKER') }}
        </p>
        <h2
          id="signup-proof-title"
          class="m-0 font-[Georgia,'Times_New_Roman',serif] text-[42px] font-normal leading-none tracking-[-0.045em] lg:text-[clamp(38px,3.6vw,54px)]"
        >
          {{ $t('REGISTER.FREEMIUM.PROOF_TITLE') }}
        </h2>
        <p
          class="mt-4 max-w-[480px] text-[13px] leading-relaxed text-[#b2c0ba]"
        >
          {{ $t('REGISTER.FREEMIUM.PROOF_DESCRIPTION') }}
        </p>
      </div>

      <ol
        class="mt-7 grid max-w-[590px] list-none grid-cols-1 p-0 sm:grid-cols-3"
        :aria-label="$t('REGISTER.FREEMIUM.SEQUENCE_LABEL')"
      >
        <li
          data-testid="freemium-sequence-step"
          class="relative min-h-[72px] border-l border-[#d7ee72]/35 py-3 pl-9 sm:min-h-[82px] sm:border-l-0 sm:border-t sm:px-3.5 sm:pb-3 sm:pt-4"
        >
          <span
            class="absolute left-2.5 top-2 text-[9px] text-[#7e8f88] sm:static"
          >
            {{ $t('REGISTER.FREEMIUM.SEQUENCE.ACCOUNT.NUMBER') }}
          </span>
          <div class="mt-1.5 grid gap-0.5 sm:mt-2">
            <strong class="text-[11px]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ACCOUNT.TITLE')
            }}</strong>
            <small class="text-[9px] text-[#8fa098]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ACCOUNT.DETAIL')
            }}</small>
          </div>
        </li>
        <li
          data-testid="freemium-sequence-step"
          class="relative min-h-[72px] border-l border-[#d7ee72]/35 py-3 pl-9 sm:min-h-[82px] sm:border-l-0 sm:border-t sm:px-3.5 sm:pb-3 sm:pt-4"
        >
          <span
            class="absolute left-2.5 top-2 text-[9px] text-[#7e8f88] sm:static"
          >
            {{ $t('REGISTER.FREEMIUM.SEQUENCE.STORE.NUMBER') }}
          </span>
          <div class="mt-1.5 grid gap-0.5 sm:mt-2">
            <strong class="text-[11px]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.STORE.TITLE')
            }}</strong>
            <small class="text-[9px] text-[#8fa098]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.STORE.DETAIL')
            }}</small>
          </div>
        </li>
        <li
          data-testid="freemium-sequence-step"
          class="relative min-h-[72px] border-l border-[#d7ee72]/35 py-3 pl-9 sm:min-h-[82px] sm:border-l-0 sm:border-t sm:px-3.5 sm:pb-3 sm:pt-4"
        >
          <span
            class="absolute left-2.5 top-2 text-[9px] text-[#7e8f88] sm:static"
          >
            {{ $t('REGISTER.FREEMIUM.SEQUENCE.ANSWER.NUMBER') }}
          </span>
          <div class="mt-1.5 grid gap-0.5 sm:mt-2">
            <strong class="text-[11px]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ANSWER.TITLE')
            }}</strong>
            <small class="text-[9px] text-[#8fa098]">{{
              $t('REGISTER.FREEMIUM.SEQUENCE.ANSWER.DETAIL')
            }}</small>
          </div>
        </li>
      </ol>

      <section
        class="mt-8 w-full max-w-[590px] overflow-hidden rounded-[22px] border border-white/15 bg-[#fffdf7] text-[#10211f] shadow-[0_28px_70px_rgba(0,0,0,.24)] lg:mt-auto"
        :aria-label="$t('REGISTER.FREEMIUM.CONVERSATION_LABEL')"
      >
        <div
          class="grid min-h-12 grid-cols-[30px_1fr_auto] items-center gap-2 border-b border-[#10211f]/10 px-3"
        >
          <span
            class="grid size-[30px] place-items-center rounded-full bg-[#dfe4ff] text-[9px] font-extrabold"
          >
            {{ $t('REGISTER.FREEMIUM.CONTACT_INITIALS') }}
          </span>
          <strong class="text-[11px]">{{
            $t('REGISTER.FREEMIUM.CONTACT_NAME')
          }}</strong>
          <img :src="IKAS_WORDMARK_URL" alt="ikas" class="h-auto w-[70px]" />
        </div>
        <p
          class="m-0 border-b border-[#10211f]/10 bg-[#f0ede4] px-3 py-2 text-[8px] text-[#596762]"
        >
          {{ $t('REGISTER.FREEMIUM.FIXTURE_DISCLOSURE') }}
        </p>
        <div class="grid gap-1.5 px-3 pb-1 pt-3 text-[10px] leading-snug">
          <p
            class="m-0 w-max max-w-[82%] justify-self-end rounded-[10px] bg-[#dfe4ff] px-2.5 py-2"
          >
            {{ $t('REGISTER.FREEMIUM.CUSTOMER_QUESTION') }}
          </p>
          <p
            class="m-0 grid w-max max-w-[82%] gap-0.5 rounded-[10px] border border-[#10211f]/10 bg-white px-2.5 py-2"
          >
            <strong class="text-[8px] uppercase tracking-[0.06em]">
              {{ $t('REGISTER.FREEMIUM.ASSISTANT_NAME') }}
            </strong>
            {{ $t('REGISTER.FREEMIUM.ASSISTANT_ANSWER') }}
          </p>
        </div>
        <div
          class="m-3 grid grid-cols-[68px_1fr] items-center gap-3 rounded-[14px] border border-[#6e8cff]/25 bg-white p-2"
        >
          <img
            data-testid="controlled-product-image"
            :src="CONTROLLED_PRODUCT_URL"
            :alt="$t('REGISTER.FREEMIUM.PRODUCT_ALT')"
            class="size-[68px] rounded-[10px] object-cover"
          />
          <div class="grid gap-1">
            <strong class="text-xs">{{
              $t('REGISTER.FREEMIUM.PRODUCT_TITLE')
            }}</strong>
            <span class="text-[9px] text-[#65726e]">{{
              $t('REGISTER.FREEMIUM.PRODUCT_SUMMARY')
            }}</span>
          </div>
        </div>
      </section>
    </aside>
  </main>
</template>
