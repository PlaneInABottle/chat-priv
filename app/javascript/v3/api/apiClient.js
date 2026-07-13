import axios from 'axios';

const { apiHost = '' } = window.kozmopathConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

export default wootAPI;
