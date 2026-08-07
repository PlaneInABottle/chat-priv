const form = document.querySelector('#signup-form');
const email = document.querySelector('#business-email');
const password = document.querySelector('#password');
const emailError = document.querySelector('#email-error');
const passwordError = document.querySelector('#password-error');
const status = document.querySelector('#form-status');
const submit = form.querySelector('button[type="submit"]');
const toggle = document.querySelector('#toggle-password');

const passwordPattern = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{6,}$/;

const setError = (input, target, message) => {
  input.setAttribute('aria-invalid', String(Boolean(message)));
  target.textContent = message;
};

const validate = () => {
  const emailValid = email.value.trim() !== '' && email.validity.valid;
  const passwordValid = passwordPattern.test(password.value);
  setError(email, emailError, emailValid ? '' : 'Geçerli bir iş e-postası gir.');
  setError(password, passwordError, passwordValid ? '' : 'Şifren tüm gereksinimleri karşılamalı.');
  return { emailValid, passwordValid };
};

toggle.addEventListener('click', () => {
  const reveal = password.type === 'password';
  password.type = reveal ? 'text' : 'password';
  toggle.textContent = reveal ? 'Gizle' : 'Göster';
  toggle.setAttribute('aria-pressed', String(reveal));
});

form.addEventListener('submit', event => {
  event.preventDefault();
  status.textContent = '';
  const result = validate();
  if (!result.emailValid) return email.focus();
  if (!result.passwordValid) return password.focus();

  submit.disabled = true;
  submit.dataset.pending = 'true';
  status.textContent = 'Prototip doğrulaması tamamlandı; ağ isteği gönderilmiyor.';

  window.setTimeout(() => {
    submit.disabled = false;
    delete submit.dataset.pending;
    status.textContent = 'Tasarım prototipi: production entegrasyonunda gerçek signup akışına bağlanacak.';
  }, 350);
});

email.addEventListener('input', () => {
  if (email.getAttribute('aria-invalid') === 'true') validate();
});
password.addEventListener('input', () => {
  if (password.getAttribute('aria-invalid') === 'true') validate();
});
