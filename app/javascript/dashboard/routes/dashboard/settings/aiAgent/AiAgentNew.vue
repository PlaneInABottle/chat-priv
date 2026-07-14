<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { createDefaultInstructionDocument } from './helpers/instructionDocument';

const store = useStore();
const { t, locale: uiLocale } = useI18n();
const router = useRouter();

const uiFlags = useMapGetter('aiAgent/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const generalInstructionContent = {
  tr: {
    instructions: `- Ürün seçimi, satış, destek, sipariş, teslimat, iade ve değişim konularında yardımcı ol ve müşteriyi uygun sonraki adıma yönlendir.
- Konuşmanın başında müşterinin amacını ve ihtiyacını belirle.
- Ürün veya hizmet seçimi gerekiyorsa kullanım amacı, gerekli özellikler, ölçü veya diğer karar bilgilerini sırayla netleştir.
- Doğrulanmış seçenekleri kısa ve karşılaştırılabilir biçimde sun; önerinin neden uygun olduğunu açıkla.
- Politika, sipariş veya teslimat sorularında yalnızca mevcut bilgiye dayan ve müşteriye izleyebileceği sonraki adımı belirt.
- Sorun çözüldüğünde kısa bir özet ver ve başka bir konuda yardıma ihtiyaç olup olmadığını sor.`,
    boundaries: `- Yanıt vermeden önce müşterinin asıl ihtiyacını belirle; eksik bilgi varsa yalnızca gerekli ve anlaşılır soruları sor.
- Yalnızca talimatlarda, bağlı bilgi kaynaklarında veya araç sonuçlarında doğrulanan şirket bilgilerini kullan.
- Ürün, fiyat, stok, kampanya, politika, teslimat tarihi veya taahhüt uydurma. Bilgi yoksa bunu açıkça söyle.
- Müşterinin ihtiyacına uygun seçenekleri gerekçesiyle açıkla; emin olmadığın bir ürünü kesin öneri gibi sunma.
- Yanıtı kolay taranır tut, müşterinin sorusunu gereksiz yere tekrarlama ve konuşmayı net bir sonraki adımla ilerlet.
- Yapılandırılmış bir işlem doğrulanmadıkça sipariş, iade, rezervasyon, ödeme veya hesap değişikliğinin tamamlandığını söyleme.
- Ödeme bilgisi, parola veya gereksiz kişisel veri isteme. Müşterinin paylaştığı hassas bilgileri yanıtta tekrar etme.
- Talep kapsam dışındaysa, bilgi çelişkiliyse veya güvenli bir yanıt veremiyorsan tahmin yürütmek yerine insan desteğine aktar.`,
  },
  en: {
    instructions: `- Help with product selection, sales, support, orders, delivery, returns, and exchanges, then guide the customer toward the appropriate next step.
- Establish the customer's goal and need at the beginning of the conversation.
- For product or service selection, clarify intended use, required features, measurements, and other decision details in a logical order.
- Present verified options in a concise, comparable format and explain why a recommendation fits.
- For policy, order, or delivery questions, rely only on available information and state the next action the customer can take.
- When the request is resolved, give a brief summary and ask whether anything else is needed.`,
    boundaries: `- Identify the customer's real need before answering. Ask only clear, necessary follow-up questions when details are missing.
- Use only company information verified by these instructions, connected knowledge, or tool results.
- Do not invent products, prices, stock, campaigns, policies, delivery dates, or commitments. Say clearly when information is unavailable.
- Explain suitable options with a reason. Do not present an uncertain product match as a definitive recommendation.
- Keep answers easy to scan, avoid repeating the question, and move the conversation toward a clear next step.
- Never claim an order, refund, booking, payment, or account change was completed unless a configured action confirms it.
- Do not request passwords, payment credentials, or unnecessary personal data. Do not repeat sensitive details back to the customer.
- Transfer to human support instead of guessing when a request is out of scope, information conflicts, or a safe answer is not possible.`,
  },
};

const currentStep = ref(0);
const generatedInstructions = ref('');
const generatedBoundaries = ref('');
const form = ref({
  name: '',
  language: 'tr',
  tone: 'friendly',
  businessContext: '',
  boundaries: '',
  instructions: '',
  inboxIds: [],
});
const errorMessage = ref('');

const steps = computed(() => [
  t('AI_ASSISTANT.CREATE.STEPS.BASICS'),
  t('AI_ASSISTANT.CREATE.STEPS.INSTRUCTIONS'),
  t('AI_ASSISTANT.CREATE.STEPS.INBOXES'),
  t('AI_ASSISTANT.CREATE.STEPS.REVIEW'),
]);

const instructionLanguage = computed(() => {
  if (['tr', 'en'].includes(form.value.language)) {
    return form.value.language;
  }

  return uiLocale.value?.toLowerCase().startsWith('tr') ? 'tr' : 'en';
});

const toneOptions = computed(() => [
  { value: 'friendly', label: t('AI_ASSISTANT.CREATE.TONES.FRIENDLY') },
  { value: 'professional', label: t('AI_ASSISTANT.CREATE.TONES.PROFESSIONAL') },
  { value: 'concise', label: t('AI_ASSISTANT.CREATE.TONES.CONCISE') },
]);

const languageOptions = computed(() => [
  {
    value: 'same_as_customer',
    label: t('AI_ASSISTANT.CREATE.LANGUAGES.SAME_AS_CUSTOMER'),
  },
  { value: 'tr', label: t('AI_ASSISTANT.CREATE.LANGUAGES.TR') },
  { value: 'en', label: t('AI_ASSISTANT.CREATE.LANGUAGES.EN') },
]);

const buildInstructions = () => {
  const content = generalInstructionContent[instructionLanguage.value];
  generatedInstructions.value = content.instructions;
  generatedBoundaries.value = content.boundaries;
  form.value.instructions = generatedInstructions.value;
  form.value.boundaries = generatedBoundaries.value;
};

const seedInstructions = () => {
  const content = generalInstructionContent[instructionLanguage.value];
  if (
    !form.value.instructions.trim() ||
    form.value.instructions === generatedInstructions.value
  ) {
    form.value.instructions = content.instructions;
    generatedInstructions.value = content.instructions;
  }
  if (
    !form.value.boundaries.trim() ||
    form.value.boundaries === generatedBoundaries.value
  ) {
    form.value.boundaries = content.boundaries;
    generatedBoundaries.value = content.boundaries;
  }
};

const validateStep = () => {
  errorMessage.value = '';
  if (currentStep.value === 0 && !form.value.name.trim()) {
    errorMessage.value = t('AI_AGENTS.NEW.NAME_REQUIRED');
  }
  if (currentStep.value === 1 && !form.value.instructions.trim()) {
    errorMessage.value = t('AI_ASSISTANT.CREATE.INSTRUCTIONS_REQUIRED');
  }
  if (currentStep.value === 2 && form.value.inboxIds.length === 0) {
    errorMessage.value = t('AI_ASSISTANT.CREATE.INBOX_REQUIRED');
  }
  return !errorMessage.value;
};

const nextStep = () => {
  if (!validateStep()) return;
  if (currentStep.value === 0) seedInstructions();
  currentStep.value += 1;
};

const previousStep = () => {
  errorMessage.value = '';
  currentStep.value = Math.max(0, currentStep.value - 1);
};

const toggleInbox = inboxId => {
  const ids = new Set(form.value.inboxIds);
  if (ids.has(inboxId)) {
    ids.delete(inboxId);
  } else {
    ids.add(inboxId);
  }
  form.value.inboxIds = Array.from(ids);
};

const buildInstructionDocument = () => {
  const language = instructionLanguage.value;
  const document = createDefaultInstructionDocument(language);
  document.profile.language = form.value.language;
  document.profile.tone = form.value.tone;

  const sectionContent = {
    identity:
      language === 'tr'
        ? `Sen, ${form.value.name} adıyla müşterilere yardımcı olan bir müşteri asistanısın.`
        : `You are ${form.value.name}, a customer-facing assistant.`,
    business_context: form.value.businessContext.trim(),
    tasks: form.value.instructions.trim(),
    rules: form.value.boundaries.trim(),
    handoff:
      language === 'tr'
        ? 'Müşteri bir insanla görüşmek istediğinde veya talep insan değerlendirmesi gerektirdiğinde konuşmayı bir insana aktar.'
        : 'If a customer asks for a person or the request needs human judgment, hand the conversation to a human.',
  };

  document.sections = { ...document.sections, ...sectionContent };
  return document;
};

const handleSubmit = async () => {
  errorMessage.value = '';
  const result = await store.dispatch('aiAgent/create', {
    name: form.value.name.trim(),
    inbox_ids: form.value.inboxIds,
    config: {
      instructions: buildInstructionDocument(),
    },
  });

  if (result && result.id) {
    useAlert(t('AI_AGENTS.NEW.SUCCESS'));
    router.push({
      name: 'ai_agent_instructions',
      params: { id: result.id },
    });
  } else if (result && result.error) {
    errorMessage.value =
      typeof result.error === 'string'
        ? result.error
        : t('AI_AGENTS.NEW.ERROR');
  } else {
    errorMessage.value = t('AI_AGENTS.NEW.ERROR');
  }
};

onMounted(() => store.dispatch('inboxes/get'));

const handleCancel = () => {
  router.push({ name: 'ai_agents' });
};
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isCreating">
    <template #header>
      <BaseSettingsHeader
        :title="t('AI_AGENTS.NEW.TITLE')"
        feature-name="ai_agent"
      />
    </template>
    <template #body>
      <div class="mx-auto flex w-full max-w-2xl flex-col gap-8">
        <ol
          class="m-0 grid list-none grid-cols-4 gap-2 p-0"
          :aria-label="t('AI_ASSISTANT.CREATE.PROGRESS')"
        >
          <li v-for="(step, index) in steps" :key="step" class="min-w-0">
            <div
              class="h-1 rounded-full"
              :class="index <= currentStep ? 'bg-n-brand' : 'bg-n-slate-4'"
            />
            <span
              class="mt-2 hidden truncate text-xs sm:block"
              :class="
                index === currentStep
                  ? 'font-medium text-n-slate-12'
                  : 'text-n-slate-10'
              "
            >
              {{ step }}
            </span>
          </li>
        </ol>

        <form class="flex flex-col gap-6" @submit.prevent="handleSubmit">
          <section v-if="currentStep === 0" class="flex flex-col gap-5">
            <div>
              <h2 class="m-0 text-xl font-semibold text-n-slate-12">
                {{ t('AI_ASSISTANT.CREATE.BASICS_TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('AI_ASSISTANT.CREATE.BASICS_HELP') }}
              </p>
            </div>
            <Input
              v-model="form.name"
              name="assistant-name"
              autocomplete="off"
              :label="t('AI_AGENTS.NEW.NAME_LABEL')"
              :placeholder="t('AI_AGENTS.NEW.NAME_PLACEHOLDER')"
              @input="errorMessage = ''"
            />
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label
                class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
              >
                {{ t('AI_ASSISTANT.CREATE.LANGUAGE') }}
                <select
                  v-model="form.language"
                  name="assistant-language"
                  class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
                >
                  <option
                    v-for="option in languageOptions"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
              </label>
              <label
                class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
              >
                {{ t('AI_ASSISTANT.CREATE.TONE') }}
                <select
                  v-model="form.tone"
                  name="assistant-tone"
                  class="h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 font-normal"
                >
                  <option
                    v-for="option in toneOptions"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
              </label>
            </div>
          </section>

          <section v-else-if="currentStep === 1" class="flex flex-col gap-5">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 class="m-0 text-xl font-semibold text-n-slate-12">
                  {{ t('AI_ASSISTANT.CREATE.INSTRUCTIONS_TITLE') }}
                </h2>
                <p class="mb-0 mt-1 text-sm text-n-slate-11">
                  {{ t('AI_ASSISTANT.CREATE.INSTRUCTIONS_HELP') }}
                </p>
              </div>
              <Button
                type="button"
                variant="outline"
                color="slate"
                icon="i-lucide-refresh-cw"
                :label="t('AI_ASSISTANT.CREATE.REBUILD')"
                @click="buildInstructions"
              />
            </div>
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
            >
              {{ t('AI_ASSISTANT.CREATE.BUSINESS_CONTEXT') }}
              <textarea
                v-model="form.businessContext"
                name="assistant-business-context"
                autocomplete="off"
                rows="4"
                class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 font-normal"
              />
            </label>
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
            >
              {{ t('AI_ASSISTANT.CREATE.INSTRUCTIONS_LABEL') }}
              <textarea
                v-model="form.instructions"
                name="assistant-tasks"
                autocomplete="off"
                rows="10"
                maxlength="50000"
                class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 font-mono text-sm font-normal leading-6"
              />
            </label>
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
            >
              {{ t('AI_ASSISTANT.CREATE.BOUNDARIES') }}
              <textarea
                v-model="form.boundaries"
                name="assistant-boundaries"
                autocomplete="off"
                rows="12"
                maxlength="50000"
                class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 font-mono text-sm font-normal leading-6"
              />
            </label>
          </section>

          <section v-else-if="currentStep === 2" class="flex flex-col gap-5">
            <div>
              <h2 class="m-0 text-xl font-semibold text-n-slate-12">
                {{ t('AI_ASSISTANT.CREATE.INBOXES_TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('AI_ASSISTANT.CREATE.INBOXES_HELP') }}
              </p>
            </div>
            <label
              v-for="inbox in inboxes"
              :key="inbox.id"
              class="flex cursor-pointer items-center gap-3 rounded-lg border border-n-weak p-3"
            >
              <input
                type="checkbox"
                :checked="form.inboxIds.includes(inbox.id)"
                @change="toggleInbox(inbox.id)"
              />
              <span class="text-sm font-medium text-n-slate-12">{{
                inbox.name
              }}</span>
            </label>
          </section>

          <section v-else class="flex flex-col gap-5">
            <div>
              <h2 class="m-0 text-xl font-semibold text-n-slate-12">
                {{ t('AI_ASSISTANT.CREATE.REVIEW_TITLE') }}
              </h2>
              <p class="mb-0 mt-1 text-sm text-n-slate-11">
                {{ t('AI_ASSISTANT.CREATE.REVIEW_HELP') }}
              </p>
            </div>
            <dl
              class="grid grid-cols-1 gap-x-4 gap-y-2 rounded-lg border border-n-weak p-4 text-sm sm:grid-cols-[140px_minmax(0,1fr)] sm:gap-y-3"
            >
              <dt class="text-n-slate-11">{{ t('AI_ASSISTANT.LIST.NAME') }}</dt>
              <dd class="m-0 text-n-slate-12">{{ form.name }}</dd>
              <dt class="text-n-slate-11">
                {{ t('AI_ASSISTANT.CREATE.LANGUAGE') }}
              </dt>
              <dd class="m-0 text-n-slate-12">
                {{
                  languageOptions.find(item => item.value === form.language)
                    ?.label
                }}
              </dd>
              <dt class="text-n-slate-11">
                {{ t('AI_ASSISTANT.CREATE.TONE') }}
              </dt>
              <dd class="m-0 text-n-slate-12">
                {{ toneOptions.find(item => item.value === form.tone)?.label }}
              </dd>
              <dt class="text-n-slate-11">
                {{ t('AI_ASSISTANT.LIST.INBOXES') }}
              </dt>
              <dd class="m-0 text-n-slate-12">{{ form.inboxIds.length }}</dd>
              <dt class="text-n-slate-11">
                {{ t('AI_ASSISTANT.CAPABILITIES.HANDOFF') }}
              </dt>
              <dd class="m-0 text-n-teal-11">
                {{ t('AI_ASSISTANT.CAPABILITIES.ALWAYS_ON') }}
              </dd>
            </dl>
          </section>

          <p
            v-if="errorMessage"
            role="alert"
            class="m-0 text-sm text-n-ruby-11"
          >
            {{ errorMessage }}
          </p>
          <div
            class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pl-10 pt-5 sm:pl-0"
          >
            <Button
              type="button"
              variant="ghost"
              color="slate"
              :label="
                currentStep === 0
                  ? t('AI_AGENTS.NEW.CANCEL')
                  : t('AI_ASSISTANT.CREATE.BACK')
              "
              @click="currentStep === 0 ? handleCancel() : previousStep()"
            />
            <Button
              v-if="currentStep < steps.length - 1"
              type="button"
              trailing-icon
              icon="i-lucide-arrow-right"
              :label="t('AI_ASSISTANT.CREATE.CONTINUE')"
              @click="nextStep"
            />
            <Button
              v-else
              type="submit"
              icon="i-lucide-message-circle-more"
              :is-loading="uiFlags.isCreating"
              :label="t('AI_ASSISTANT.CREATE.CREATE_DRAFT')"
            />
          </div>
        </form>
      </div>
    </template>
  </SettingsLayout>
</template>
