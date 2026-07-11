(() => {
  const OPENAI_REALTIME_VOICES = [
    'alloy',
    'ash',
    'ballad',
    'coral',
    'echo',
    'sage',
    'shimmer',
    'verse',
    'marin',
    'cedar',
  ];

  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-voice-runtime-card]').forEach(card => {
      const provider = card.querySelector('[data-voice-runtime-provider]');
      const model = card.querySelector('[data-voice-runtime-model]');
      const voice = card.querySelector('[data-voice-runtime-voice]');
      if (!provider || !model || !voice) return;

      provider.addEventListener('change', () => {
        if (provider.value === 'openai') {
          model.value = 'gpt-realtime-2.1';
          if (!OPENAI_REALTIME_VOICES.includes(voice.value)) {
            voice.value = 'marin';
          }
          return;
        }

        if (model.value === 'gpt-realtime-2.1') model.value = '';
        if (OPENAI_REALTIME_VOICES.includes(voice.value)) {
          voice.value = 'Charon';
        }
      });
    });
  });
})();
