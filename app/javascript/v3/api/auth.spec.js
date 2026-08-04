import {
  clearLocalStorageOnLogout,
  setAuthCredentials,
} from 'dashboard/store/utils/api';
import { replaceRouteWithReload } from '../helpers/CommonHelper';
import {
  getCredentialsFromEmail,
  getLoginRedirectURL,
} from '../helpers/AuthHelper';
import wootAPI from './apiClient';
import { register } from './auth';

vi.mock('dashboard/store/utils/api', () => ({
  clearLocalStorageOnLogout: vi.fn(),
  setAuthCredentials: vi.fn(),
  throwErrorMessage: vi.fn(error => {
    throw error;
  }),
}));
vi.mock('../helpers/CommonHelper', () => ({ replaceRouteWithReload: vi.fn() }));
vi.mock('../helpers/AuthHelper', () => ({
  getCredentialsFromEmail: vi.fn(),
  getLoginRedirectURL: vi.fn(),
}));
vi.mock('./apiClient', () => ({ default: { post: vi.fn() } }));

describe('register', () => {
  const credentials = {
    email: 'owner@acme.com',
    password: 'Password1!',
    hCaptchaClientResponse: '',
  };

  beforeEach(() => {
    getCredentialsFromEmail.mockReturnValue({
      fullName: 'Owner',
      accountName: 'Acme',
    });
  });

  it('stores credentials and redirects an authenticated signup', async () => {
    const response = {
      data: { data: { account_id: 7, accounts: [{ id: 7 }] } },
      headers: {
        'access-token': 'test-access-token',
        client: 'test-client',
        expiry: '9999999999',
        uid: credentials.email,
      },
    };
    wootAPI.post.mockResolvedValue(response);
    getLoginRedirectURL.mockReturnValue('/app/accounts/7/dashboard');

    const result = await register(credentials);

    expect(setAuthCredentials).toHaveBeenCalledWith(response);
    expect(clearLocalStorageOnLogout).toHaveBeenCalledTimes(1);
    expect(getLoginRedirectURL).toHaveBeenCalledWith({
      user: response.data.data,
    });
    expect(replaceRouteWithReload).toHaveBeenCalledWith(
      '/app/accounts/7/dashboard'
    );
    expect(result).toEqual({ authenticated: true });
  });

  it('returns a confirmation-required result without storing credentials', async () => {
    wootAPI.post.mockResolvedValue({
      data: { email: credentials.email },
      headers: {},
    });

    const result = await register(credentials);

    expect(setAuthCredentials).not.toHaveBeenCalled();
    expect(clearLocalStorageOnLogout).not.toHaveBeenCalled();
    expect(replaceRouteWithReload).not.toHaveBeenCalled();
    expect(result).toEqual({
      authenticated: false,
      email: credentials.email,
    });
  });
});
