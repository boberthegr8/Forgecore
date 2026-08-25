import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.112.4';

const FORGE_CORE_URL = 'https://uyqanhwurngoupmvzxrh.supabase.co';
const FORGE_CORE_PUBLISHABLE_KEY = 'sb_publishable_SquKrj848EoO9NHZknVkSA_k8CKD7WQ';
const DEFAULT_LOCATION_CODE = 'JK-MAIN';

const supabase = createClient(FORGE_CORE_URL, FORGE_CORE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});

const loadingView = document.getElementById('loading-view');
const loginView = document.getElementById('login-view');
const homeView = document.getElementById('home-view');
const emailInput = document.getElementById('email-input');
const loginButton = document.getElementById('login-button');
const loginMessage = document.getElementById('login-message');
const logoutButton = document.getElementById('logout-button');
const orgName = document.getElementById('org-name');
const locationName = document.getElementById('location-name');

const rememberedEmail = window.localStorage.getItem('forge_home_email');
if (rememberedEmail) emailInput.value = rememberedEmail;

function showOnly(view) {
  for (const node of [loadingView, loginView, homeView]) node.classList.add('hidden');
  view.classList.remove('hidden');
}

function showMessage(text, isError = false) {
  loginMessage.textContent = text;
  loginMessage.classList.remove('hidden', 'error');
  if (isError) loginMessage.classList.add('error');
}

function clearMessage() {
  loginMessage.textContent = '';
  loginMessage.classList.add('hidden');
  loginMessage.classList.remove('error');
}

async function loadOwnerWorkspace(user) {
  const { data: memberships, error: membershipError } = await supabase
    .from('organization_memberships')
    .select('organization_id,role,status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .limit(1);

  if (membershipError) throw membershipError;
  const membership = memberships?.[0];
  if (!membership || membership.role !== 'owner') {
    await supabase.auth.signOut();
    throw new Error('Forge Home is currently restricted to the Rob owner account.');
  }

  const [organizationResult, locationsResult] = await Promise.all([
    supabase.from('organizations').select('id,name,status').eq('id', membership.organization_id).single(),
    supabase.from('locations').select('id,name,code,status').eq('organization_id', membership.organization_id).eq('status', 'active').order('name')
  ]);

  if (organizationResult.error) throw organizationResult.error;
  if (locationsResult.error) throw locationsResult.error;

  const locations = locationsResult.data || [];
  const location = locations.find(row => row.code === DEFAULT_LOCATION_CODE) || locations[0];

  orgName.textContent = organizationResult.data?.name || 'Forge Core';
  locationName.textContent = location?.name || 'Organization-wide';
  showOnly(homeView);
}

async function refreshAuthState() {
  try {
    const { data, error } = await supabase.auth.getUser();
    if (error && error.name !== 'AuthSessionMissingError') throw error;
    if (!data?.user) {
      showOnly(loginView);
      return;
    }
    await loadOwnerWorkspace(data.user);
  } catch (error) {
    console.error('Forge Home auth error', error);
    showOnly(loginView);
    showMessage(error?.message || 'Forge Home could not verify the owner session.', true);
  }
}

async function sendMagicLink() {
  const email = emailInput.value.trim();
  clearMessage();
  if (!email) {
    showMessage('Enter the email attached to the Rob Forge account.', true);
    return;
  }

  loginButton.disabled = true;
  loginButton.querySelector('span:first-child').textContent = 'Sending sign-in link…';
  try {
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: false,
        emailRedirectTo: window.location.origin
      }
    });
    if (error) throw error;
    window.localStorage.setItem('forge_home_email', email);
    showMessage('Sign-in link sent. Open the Forge email on this device to enter Forge Home.');
  } catch (error) {
    showMessage(error?.message || 'Could not send the Forge sign-in link.', true);
  } finally {
    loginButton.disabled = false;
    loginButton.querySelector('span:first-child').textContent = 'Send passwordless sign-in link';
  }
}

loginButton.addEventListener('click', () => void sendMagicLink());
emailInput.addEventListener('keydown', event => {
  if (event.key === 'Enter') void sendMagicLink();
});

logoutButton.addEventListener('click', async () => {
  logoutButton.disabled = true;
  try {
    await supabase.auth.signOut();
    showOnly(loginView);
  } finally {
    logoutButton.disabled = false;
  }
});

supabase.auth.onAuthStateChange((_event, session) => {
  window.setTimeout(() => {
    if (session?.user) void loadOwnerWorkspace(session.user).catch(error => {
      showOnly(loginView);
      showMessage(error?.message || 'Forge Home could not verify the owner session.', true);
    });
  }, 0);
});

void refreshAuthState();
