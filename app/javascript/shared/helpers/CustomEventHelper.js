export const createEvent = ({ eventName, data = null }) => {
  let event;
  if (typeof window.CustomEvent === 'function') {
    event = new CustomEvent(eventName, { detail: data });
  } else {
    event = document.createEvent('CustomEvent');
    event.initCustomEvent(eventName, false, false, data);
  }
  return event;
};

export const dispatchWindowEvent = ({ eventName, data }) => {
  const eventNames = [eventName];
  if (eventName.startsWith('kozmopath:')) {
    eventNames.push(eventName.replace('kozmopath:', 'chatwoot:'));
  }

  eventNames.forEach(name => {
    const event = createEvent({ eventName: name, data });
    window.dispatchEvent(event);
  });
};
