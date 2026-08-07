const closePrototypeMenu = event => {
  if (!event.target.closest('.mobile-menu a')) return;
  event.target.closest('.mobile-menu')?.removeAttribute('open');
};

document.addEventListener('click', closePrototypeMenu);
