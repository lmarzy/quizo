import React, { useEffect, useMemo, useRef, useState } from 'react';
import ReactDOM from 'react-dom/client';
import { AlertTriangle, ArrowLeft, BookOpen, CheckCircle2, Clipboard, Lock, LogOut, PartyPopper, Pencil, Play, Plus, RefreshCw, Save, Search, Send, Trash2, User, UserPlus, Volume2, VolumeX, X } from 'lucide-react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './lib/supabase';
import './styles.css';

type Profile = {
  id: string;
  email: string | null;
  display_name: string | null;
};

type QuestionPack = {
  id: string;
  owner_user_id: string | null;
  name: string;
  description: string | null;
  visibility: string;
  tier: string;
};

type PracticeQuestion = {
  id: string;
  prompt: string;
  option_a: string;
  option_b: string;
  option_c: string;
  correct_option: string;
};

type PracticeAnswer = {
  question: PracticeQuestion;
  selectedOption: string;
  isCorrect: boolean;
};

type Subscription = {
  plan_id: string;
  status: string;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  billing_interval: string | null;
  billing_amount_cents: number | null;
  currency: string | null;
};

type PlanId = 'free' | 'pro' | 'creator';
type BillingInterval = 'monthly' | 'quarterly' | 'yearly';

const planNames: Record<PlanId, string> = {
  free: 'Free',
  pro: 'Pro',
  creator: 'Creator',
};

const planPlayerLimits: Record<PlanId, number> = {
  free: 6,
  pro: 20,
  creator: 50,
};

const upgradePlans: Array<{
  id: Exclude<PlanId, 'free'>;
  description: string;
  features: string[];
  prices: Record<BillingInterval, number>;
}> = [
  {
    id: 'pro',
    description: 'For hosts who want more variety and bigger games.',
    features: ['More question packs', 'Up to 20 players per game', 'More hosted games'],
    prices: { monthly: 699, quarterly: 1799, yearly: 5999 },
  },
  {
    id: 'creator',
    description: 'For hosts who want to create their own quiz content.',
    features: ['Everything in Pro', 'Up to 50 players per game', 'Custom question packs'],
    prices: { monthly: 1499, quarterly: 3999, yearly: 12999 },
  },
];

const billingIntervals: Array<{ id: BillingInterval; label: string; suffix: string }> = [
  { id: 'monthly', label: 'Monthly', suffix: '/month' },
  { id: 'quarterly', label: '3 months', suffix: '/3 months' },
  { id: 'yearly', label: 'Yearly', suffix: '/year' },
];

function normalisePlanId(planId?: string | null): PlanId {
  if (planId === 'pro' || planId === 'creator') return planId;
  return 'free';
}

function getPlanLabel(planId?: string | null) {
  return `${planNames[normalisePlanId(planId)]} plan`;
}

function getPackTierLabel(tier: string) {
  if (tier === 'creator') return 'Creator';
  if (tier === 'pro') return 'Pro';
  return 'Free';
}

function isProGameMode(mode: string) {
  return mode === 'speed_round' || mode === 'elimination_ladder';
}

function formatBillingDate(value?: string | null) {
  if (!value) return 'Not scheduled';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
}

function formatMoney(cents?: number | null, currency = 'gbp') {
  if (!cents) return 'Included';
  return new Intl.NumberFormat(undefined, { style: 'currency', currency: currency.toUpperCase() }).format(cents / 100);
}

function getPublicAppUrl() {
  const configuredUrl = import.meta.env.VITE_PUBLIC_APP_URL?.trim();
  const fallbackUrl = typeof window === 'undefined' ? '' : window.location.origin;
  return (configuredUrl || fallbackUrl).replace(/\/+$/, '');
}

function getJoinUrl(joinCode: string) {
  return `${getPublicAppUrl()}/join/${joinCode}`;
}

type Game = {
  id: string;
  name: string;
  join_code: string;
  status: string;
  game_mode: string;
  question_pack_id: string | null;
  starting_points: number;
  target_points: number;
  elimination_rounds: number;
  questions_per_round: number;
  wrong_answer_penalty: number;
  recovery_points: number;
  question_time_limit_seconds: number;
  current_member_id: string | null;
  current_question_id: string | null;
  current_turn_attempt?: number;
  max_consecutive_questions: number;
  timer_ends_at: string | null;
  created_at: string;
};

type GameMember = {
  id: string;
  game_id: string;
  user_id: string | null;
  display_name: string;
  invite_token: string;
  points: number;
  status: string;
  turn_order: number;
};

type GameAnswerSummary = {
  id: string;
  member_id: string;
  question_id: string;
  selected_option: string;
  is_correct: boolean;
  points_delta: number;
  answered_at: string;
  game_members?: { display_name: string } | null;
  questions?: {
    prompt: string;
    correct_option: string;
    option_a: string;
    option_b: string;
    option_c: string;
  } | null;
};

type AuthMode = 'sign-in' | 'sign-up';

type MemberDraft = {
  display_name: string;
  points: number;
  turn_order: number;
};

type GameSettingsDraft = {
  name: string;
  game_mode: string;
  question_pack_id: string;
  starting_points: number;
  target_points: number;
  elimination_rounds: number;
  questions_per_round: number;
  wrong_answer_penalty: number;
  recovery_points: number;
  question_time_limit_seconds: number;
  max_consecutive_questions: number;
};

type ToastState = {
  id: number;
  message: string;
  tone: 'success' | 'error';
};

type ConfirmDialogState = {
  title: string;
  message: string;
  confirmLabel: string;
  tone: 'danger' | 'primary';
  onConfirm: () => Promise<void>;
};

type GameMode = 'classic' | 'race_to_points' | 'speed_round' | 'elimination_ladder';

const defaultForm = {
  name: '',
  gameMode: 'classic' as GameMode,
  questionPackId: '',
  startingPoints: 100,
  targetPoints: 150,
  eliminationRounds: 3,
  questionsPerRound: 3,
  wrongPenalty: 10,
  recoveryPoints: 10,
  timeLimit: 10,
  maxConsecutiveQuestions: 2,
};

const RESULT_TOAST_DURATION_MS = 3600;
const LADDER_ROUND_RESULT_DURATION_MS = 5200;
const SOUND_PREFERENCE_KEY = 'quizo_game_sound_enabled';

function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [loadingSession, setLoadingSession] = useState(true);
  const joinCode = getJoinCodeFromPath();

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoadingSession(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  if (loadingSession) {
    return <Shell status="Checking your session..." />;
  }

  if (joinCode) {
    return <JoinGame joinCode={joinCode} />;
  }

  return session ? <Dashboard session={session} /> : <AuthScreen />;
}

function getJoinCodeFromPath() {
  const match = window.location.pathname.match(/^\/join\/([^/]+)$/);
  return match?.[1]?.toUpperCase() || '';
}

function Shell({ status }: { status: string }) {
  return (
    <main className="shell loading-shell">
      <div className="loading-card" role="status" aria-live="polite">
        <div className="brand-mark loading-brand-mark">
          <LogoMark size={34} />
        </div>
        <div>
          <p className="eyebrow">Quizo</p>
          <h1>Getting the room ready</h1>
          <p>{status}</p>
        </div>
        <div className="loading-progress" aria-hidden="true">
          <span />
        </div>
        <LoadingDots />
      </div>
    </main>
  );
}

function LoadingDots() {
  return (
    <div className="loading-dots" aria-hidden="true">
      <span />
      <span />
      <span />
    </div>
  );
}

function LogoMark({ size = 28 }: { size?: number }) {
  return (
    <svg className="quizo-logo-mark" width={size} height={size} viewBox="0 0 64 64" role="img" aria-label="Quizo">
      <path className="quizo-logo-ring" d="M31.5 9.5C18.5 9.5 8.5 19.3 8.5 32s10 22.5 23 22.5c5.1 0 9.7-1.5 13.4-4.2" />
      <path className="quizo-logo-tail" d="M43.5 43.5 55 55" />
      <path className="quizo-logo-check" d="m20.5 31.5 6 6 16-17" />
      <circle className="quizo-logo-dot" cx="48" cy="17" r="5.5" />
    </svg>
  );
}

function AuthScreen() {
  const [mode, setMode] = useState<AuthMode>('sign-in');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const nextDisplayName = displayName.trim();

    if (mode === 'sign-up' && nextDisplayName.length < 2) {
      setMessage('Add a display name with at least 2 characters.');
      return;
    }

    setBusy(true);
    setMessage('');

    const response =
      mode === 'sign-up'
        ? await supabase.auth.signUp({
            email,
            password,
            options: {
              data: { display_name: nextDisplayName },
            },
          })
        : await supabase.auth.signInWithPassword({ email, password });

    setBusy(false);

    if (response.error) {
      setMessage(response.error.message);
      return;
    }

    setMessage(mode === 'sign-up' ? 'Account created. Check your email if confirmation is enabled.' : 'Signed in.');
  }

  return (
    <main className="auth-layout">
      <section className="auth-intro">
        <div className="brand-row">
          <div className="brand-mark">
            <LogoMark size={32} />
          </div>
          <span>Quizo</span>
        </div>
        <h1>Live quiz rooms for groups that like a little pressure.</h1>
        <p>Create a game, choose a question pack, invite members, and keep everyone watching the same live scoreboard.</p>
      </section>

      <section className="auth-panel">
        <div className="mode-switch" aria-label="Authentication mode">
          <button className={mode === 'sign-in' ? 'active' : ''} onClick={() => setMode('sign-in')} type="button">
            Sign in
          </button>
          <button className={mode === 'sign-up' ? 'active' : ''} onClick={() => setMode('sign-up')} type="button">
            Sign up
          </button>
        </div>

        <form onSubmit={handleSubmit} className="stack">
          {mode === 'sign-up' && (
            <label>
              Display name
              <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="Lee" minLength={2} required />
            </label>
          )}
          <label>
            Email
            <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required />
          </label>
          <label>
            Password
            <input
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              type="password"
              minLength={6}
              required
            />
          </label>
          <button className="primary-button" disabled={busy} type="submit">
            {busy ? <RefreshCw className="spin" size={18} /> : <CheckCircle2 size={18} />}
            {mode === 'sign-up' ? 'Create account' : 'Sign in'}
          </button>
          {message && <p className="form-message">{message}</p>}
        </form>
      </section>
    </main>
  );
}

function Dashboard({ session }: { session: Session }) {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [subscription, setSubscription] = useState<Subscription | null>(null);
  const [packs, setPacks] = useState<QuestionPack[]>([]);
  const [packQuestionCounts, setPackQuestionCounts] = useState<Record<string, number>>({});
  const [games, setGames] = useState<Game[]>([]);
  const [dashboardLoading, setDashboardLoading] = useState(true);
  const [memberStats, setMemberStats] = useState<Record<string, { players: number; joined: number }>>({});
  const [members, setMembers] = useState<GameMember[]>([]);
  const [selectedGameId, setSelectedGameId] = useState('');
  const [memberNames, setMemberNames] = useState('');
  const [form, setForm] = useState(defaultForm);
  const [busy, setBusy] = useState(false);
  const [memberBusy, setMemberBusy] = useState(false);
  const [startBusy, setStartBusy] = useState(false);
  const [gameActionBusy, setGameActionBusy] = useState('');
  const [memberActionBusy, setMemberActionBusy] = useState('');
  const [editingMemberId, setEditingMemberId] = useState('');
  const [memberDrafts, setMemberDrafts] = useState<Record<string, MemberDraft>>({});
  const [gameSettingsDraft, setGameSettingsDraft] = useState<GameSettingsDraft | null>(null);
  const [gameSettingsBusy, setGameSettingsBusy] = useState(false);
  const [wizardOpen, setWizardOpen] = useState(false);
  const [wizardStep, setWizardStep] = useState(1);
  const [includeHostAsPlayer, setIncludeHostAsPlayer] = useState(false);
  const [accountMenuOpen, setAccountMenuOpen] = useState(false);
  const [activeView, setActiveView] = useState<'games' | 'profile'>('games');
  const [accountNameDraft, setAccountNameDraft] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [accountBusy, setAccountBusy] = useState(false);
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [planActionBusy, setPlanActionBusy] = useState<PlanId | ''>('');
  const [upgradeOpen, setUpgradeOpen] = useState(false);
  const [practiceOpen, setPracticeOpen] = useState(false);
  const [packsDrawerOpen, setPacksDrawerOpen] = useState(false);
  const [manageDrawerOpen, setManageDrawerOpen] = useState(false);
  const [controlRoomGame, setControlRoomGame] = useState<Game | null>(null);
  const [summaryGame, setSummaryGame] = useState<Game | null>(null);
  const [summaryMembers, setSummaryMembers] = useState<GameMember[]>([]);
  const [summaryAnswers, setSummaryAnswers] = useState<GameAnswerSummary[]>([]);
  const [summaryBusy, setSummaryBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [wizardNotice, setWizardNotice] = useState('');
  const [memberNotice, setMemberNotice] = useState('');
  const [toast, setToast] = useState<ToastState | null>(null);
  const [confirmDialog, setConfirmDialog] = useState<ConfirmDialogState | null>(null);
  const [confirmBusy, setConfirmBusy] = useState(false);

  const selectedGame = useMemo(() => games.find((game) => game.id === selectedGameId) || null, [games, selectedGameId]);
  const currentPlanId = normalisePlanId(subscription?.plan_id);
  const planLabel = getPlanLabel(currentPlanId);
  const hasActivePaidPlan = Boolean(subscription && ['active', 'trialing'].includes(subscription.status));
  const maxPlayersPerGame = planPlayerLimits[hasActivePaidPlan ? currentPlanId : 'free'];
  const canUseProPacks = hasActivePaidPlan && ['pro', 'creator'].includes(currentPlanId);
  const canUseProModes = canUseProPacks;
  const canUseCreatorFeatures = hasActivePaidPlan && currentPlanId === 'creator';
  const usablePacks = useMemo(
    () => packs.filter((pack) => pack.tier === 'free' || (pack.tier === 'pro' && canUseProPacks) || (pack.tier === 'creator' && canUseCreatorFeatures)),
    [canUseCreatorFeatures, canUseProPacks, packs],
  );
  const selectedJoinUrl = selectedGame ? getJoinUrl(selectedGame.join_code) : '';
  const authDisplayName = typeof session.user.user_metadata?.display_name === 'string' ? session.user.user_metadata.display_name : '';
  const hostDisplayName = profile?.display_name || authDisplayName || 'Host';
  const accountEmail = profile?.email || session.user.email || '';
  const accountInitials = hostDisplayName
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');
  const joinedMemberCount = useMemo(() => members.filter((member) => member.status === 'joined').length, [members]);
  const activeOrJoinedMemberCount = useMemo(() => members.filter((member) => ['active', 'joined'].includes(member.status)).length, [members]);
  const hostMember = useMemo(() => members.find((member) => member.game_id === selectedGameId && member.user_id === session.user.id) || null, [members, selectedGameId, session.user.id]);
  const canManageSelectedGame = Boolean(selectedGame && ['draft', 'lobby'].includes(selectedGame.status));
  const canStartSelectedGame = Boolean(selectedGame && ['draft', 'lobby'].includes(selectedGame.status) && joinedMemberCount >= 2);
  const activeGames = useMemo(() => games.filter((game) => !['finished', 'cancelled'].includes(game.status)), [games]);
  const completedGames = useMemo(() => games.filter((game) => ['finished', 'cancelled'].includes(game.status)), [games]);
  const overlayOpen = wizardOpen || upgradeOpen || practiceOpen || packsDrawerOpen || manageDrawerOpen || Boolean(controlRoomGame) || Boolean(summaryGame) || Boolean(confirmDialog);

  useEffect(() => {
    void loadDashboard();
  }, []);

  useEffect(() => {
    if (!overlayOpen) return undefined;

    const { body, documentElement } = document;
    const scrollY = window.scrollY;
    const previousBodyOverflow = body.style.overflow;
    const previousBodyPaddingRight = body.style.paddingRight;
    const previousBodyPosition = body.style.position;
    const previousBodyTop = body.style.top;
    const previousBodyWidth = body.style.width;
    const previousDocumentOverflow = documentElement.style.overflow;
    const previousDocumentOverscroll = documentElement.style.overscrollBehavior;
    const scrollbarWidth = window.innerWidth - documentElement.clientWidth;

    body.style.overflow = 'hidden';
    body.style.position = 'fixed';
    body.style.top = `-${scrollY}px`;
    body.style.width = '100%';
    documentElement.style.overflow = 'hidden';
    documentElement.style.overscrollBehavior = 'contain';

    if (scrollbarWidth > 0) {
      body.style.paddingRight = `${scrollbarWidth}px`;
    }

    return () => {
      body.style.overflow = previousBodyOverflow;
      body.style.paddingRight = previousBodyPaddingRight;
      body.style.position = previousBodyPosition;
      body.style.top = previousBodyTop;
      body.style.width = previousBodyWidth;
      documentElement.style.overflow = previousDocumentOverflow;
      documentElement.style.overscrollBehavior = previousDocumentOverscroll;
      window.scrollTo(0, scrollY);
    };
  }, [overlayOpen]);

  useEffect(() => {
    setAccountNameDraft(hostDisplayName);
  }, [hostDisplayName]);

  useEffect(() => {
    if (!toast) return undefined;

    const toastTimer = window.setTimeout(() => setToast(null), 3200);
    return () => window.clearTimeout(toastTimer);
  }, [toast]);

  useEffect(() => {
    if (selectedGameId) {
      void loadMembers(selectedGameId);
    } else {
      setMembers([]);
    }
  }, [selectedGameId]);

  useEffect(() => {
    if (!selectedGame) {
      setGameSettingsDraft(null);
      return;
    }

    setGameSettingsDraft({
      name: selectedGame.name,
      game_mode: selectedGame.game_mode || 'classic',
      question_pack_id: selectedGame.question_pack_id || packs[0]?.id || '',
      starting_points: selectedGame.starting_points,
      target_points: selectedGame.target_points || 100,
      elimination_rounds: selectedGame.elimination_rounds || 3,
      questions_per_round: selectedGame.questions_per_round || 3,
      wrong_answer_penalty: selectedGame.wrong_answer_penalty,
      recovery_points: selectedGame.recovery_points,
      question_time_limit_seconds: selectedGame.question_time_limit_seconds,
      max_consecutive_questions: selectedGame.max_consecutive_questions,
    });
  }, [packs, selectedGame]);

  useEffect(() => {
    if (!selectedGameId) return undefined;

    const refreshLobby = () => {
      void loadMembers(selectedGameId);
      void loadDashboard();
    };

    const channel = supabase
      .channel(`host-lobby-${selectedGameId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'game_members', filter: `game_id=eq.${selectedGameId}` },
        () => void loadMembers(selectedGameId),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'games', filter: `id=eq.${selectedGameId}` },
        () => void loadDashboard(),
      )
      .subscribe();

    const pollId = window.setInterval(refreshLobby, 5000);
    window.addEventListener('focus', refreshLobby);

    return () => {
      window.clearInterval(pollId);
      window.removeEventListener('focus', refreshLobby);
      void supabase.removeChannel(channel);
    };
  }, [selectedGameId]);

  async function loadDashboard() {
    try {
      const [profileResult, subscriptionResult, gamesResult] = await Promise.all([
        supabase.from('profiles').select('id,email,display_name').eq('id', session.user.id).single(),
        supabase.from('subscriptions').select('plan_id,status,current_period_end,cancel_at_period_end,billing_interval,billing_amount_cents,currency').eq('user_id', session.user.id).single(),
        supabase
          .from('games')
          .select(
            'id,name,join_code,status,game_mode,question_pack_id,starting_points,target_points,elimination_rounds,questions_per_round,wrong_answer_penalty,recovery_points,question_time_limit_seconds,current_member_id,current_question_id,current_turn_attempt,max_consecutive_questions,timer_ends_at,created_at',
          )
          .order('created_at', { ascending: false }),
      ]);

      if (profileResult.data) setProfile(profileResult.data);
      if (subscriptionResult.data) setSubscription(subscriptionResult.data);
      if (gamesResult.data) {
        setGames(gamesResult.data);
        setSelectedGameId((current) => current || gamesResult.data[0]?.id || '');

        if (gamesResult.data.length > 0) {
          const { data: statRows } = await supabase.from('game_members').select('game_id,status').in(
            'game_id',
            gamesResult.data.map((game) => game.id),
          );
          const nextStats = (statRows || []).reduce<Record<string, { players: number; joined: number }>>((stats, row) => {
            const current = stats[row.game_id] || { players: 0, joined: 0 };
            return {
              ...stats,
              [row.game_id]: {
                players: current.players + 1,
                joined: current.joined + (row.status === 'joined' || row.status === 'active' ? 1 : 0),
              },
            };
          }, {});
          setMemberStats(nextStats);
        } else {
          setMemberStats({});
        }
      }

      await loadQuestionPacks();
    } finally {
      setDashboardLoading(false);
    }
  }

  async function loadQuestionPacks() {
    const [packsResult, questionsResult] = await Promise.all([
      supabase
        .from('question_packs')
        .select('id,owner_user_id,name,description,visibility,tier')
        .is('owner_user_id', null)
        .order('owner_user_id', { ascending: true, nullsFirst: false })
        .order('tier')
        .order('name'),
      supabase.from('questions').select('pack_id'),
    ]);

    if (packsResult.error) {
      showToast(packsResult.error.message, 'error');
      return;
    }

    if (questionsResult.error) {
      showToast(questionsResult.error.message, 'error');
      return;
    }

    const starterPackOrder = ['General Knowledge', 'Family Fun', 'Movies and TV', 'Sports Night', 'Music Legends', 'Geography', 'History', 'Science and Nature', 'Food and Drink', '90s and 00s', 'Custom Pack Builder'];
    const nextPacks = [...(packsResult.data || [])].sort(
      (a, b) => {
        const tierOrder = ['free', 'pro', 'creator'];
        const tierSort = tierOrder.indexOf(a.tier) - tierOrder.indexOf(b.tier);
        if (tierSort !== 0) return tierSort;
        return (starterPackOrder.indexOf(a.name) === -1 ? 99 : starterPackOrder.indexOf(a.name)) - (starterPackOrder.indexOf(b.name) === -1 ? 99 : starterPackOrder.indexOf(b.name));
      },
    );
    const nextCounts = (questionsResult.data || []).reduce<Record<string, number>>((counts, question) => {
      counts[question.pack_id] = (counts[question.pack_id] || 0) + 1;
      return counts;
    }, {});

    setPacks(nextPacks);
    setPackQuestionCounts(nextCounts);
    setForm((current) => ({
      ...current,
      questionPackId: nextPacks.some((pack) => pack.id === current.questionPackId && pack.tier === 'free') ? current.questionPackId : nextPacks.find((pack) => pack.tier === 'free')?.id || '',
    }));
  }

  async function loadMembers(gameId: string) {
    const { data, error } = await supabase
      .from('game_members')
      .select('id,game_id,user_id,display_name,invite_token,points,status,turn_order')
      .eq('game_id', gameId)
      .order('turn_order', { ascending: true })
      .order('created_at', { ascending: true });

    if (error) {
      setMemberNotice(error.message);
      return;
    }

    setMembers(data || []);
  }

  async function openGameSummary(game: Game) {
    setSummaryGame(game);
    setSummaryMembers([]);
    setSummaryAnswers([]);
    setSummaryBusy(true);

    const [membersResult, answersResult] = await Promise.all([
      supabase
        .from('game_members')
        .select('id,game_id,user_id,display_name,invite_token,points,status,turn_order')
        .eq('game_id', game.id)
        .order('points', { ascending: false })
        .order('turn_order', { ascending: true }),
      supabase
        .from('game_answers')
        .select(
          'id,member_id,question_id,selected_option,is_correct,points_delta,answered_at,game_members(display_name),questions(prompt,correct_option,option_a,option_b,option_c)',
        )
        .eq('game_id', game.id)
        .order('answered_at', { ascending: true }),
    ]);

    setSummaryBusy(false);

    if (membersResult.error) {
      showToast(membersResult.error.message, 'error');
      return;
    }

    if (answersResult.error) {
      showToast(answersResult.error.message, 'error');
      return;
    }

    setSummaryMembers(membersResult.data || []);
    setSummaryAnswers(
      ((answersResult.data || []) as Array<
        Omit<GameAnswerSummary, 'game_members' | 'questions'> & {
          game_members?: { display_name: string }[] | { display_name: string } | null;
          questions?: GameAnswerSummary['questions'][] | GameAnswerSummary['questions'];
        }
      >).map((answer) => ({
        ...answer,
        game_members: Array.isArray(answer.game_members) ? answer.game_members[0] || null : answer.game_members || null,
        questions: Array.isArray(answer.questions) ? answer.questions[0] || null : answer.questions || null,
      })),
    );
  }

  function openGameWizard() {
    setNotice('');
    setMemberNotice('');
    setWizardNotice('');
    setWizardStep(1);
    setWizardOpen(true);
  }

  function showToast(message: string, tone: ToastState['tone'] = 'success') {
    setToast({ id: Date.now(), message, tone });
  }

  async function runConfirmedAction() {
    if (!confirmDialog) return;

    setConfirmBusy(true);
    await confirmDialog.onConfirm();
    setConfirmBusy(false);
    setConfirmDialog(null);
  }

  async function createGame() {
    if (!form.name.trim() || !form.questionPackId) {
      setWizardNotice('Add a game name and question pack.');
      return;
    }

    const isTargetMode = form.gameMode === 'classic' || form.gameMode === 'race_to_points' || form.gameMode === 'speed_round';
    const isEliminationMode = form.gameMode === 'elimination_ladder';

    if (isProGameMode(form.gameMode) && !canUseProModes) {
      setWizardNotice('Upgrade to Pro to create Speed Round or Elimination Ladder games.');
      setWizardStep(1);
      return;
    }

    if (
      form.startingPoints < 0 ||
      (form.gameMode === 'classic' && (form.startingPoints <= 0 || form.targetPoints <= form.startingPoints)) ||
      ((form.gameMode === 'race_to_points' || form.gameMode === 'speed_round') && form.targetPoints <= 0) ||
      form.timeLimit < 5 ||
      form.maxConsecutiveQuestions < 1 ||
      (isEliminationMode && (form.eliminationRounds < 1 || form.questionsPerRound < 1))
    ) {
      setWizardNotice('Check the rules before creating the game.');
      setWizardStep(2);
      return;
    }

    const names = memberNames
      .split(/\n|,/)
      .map((name) => name.trim())
      .filter(Boolean);
    const hostNameKey = hostDisplayName.toLowerCase();
    const uniqueNames = [...new Set(names)].filter((name) => !includeHostAsPlayer || name.toLowerCase() !== hostNameKey);

    if (uniqueNames.length + (includeHostAsPlayer ? 1 : 0) === 0) {
      setWizardNotice('Add at least one player before creating the game.');
      setWizardStep(3);
      return;
    }

    if (uniqueNames.length + (includeHostAsPlayer ? 1 : 0) > maxPlayersPerGame) {
      setWizardNotice(`${planLabel} supports up to ${maxPlayersPerGame} players per game.`);
      setWizardStep(3);
      return;
    }

    setBusy(true);
    setWizardNotice('');

    const { data, error } = await supabase.from('games').insert({
      host_user_id: session.user.id,
      question_pack_id: form.questionPackId || null,
      name: form.name.trim(),
      join_code: '',
      game_mode: form.gameMode,
      starting_points: form.startingPoints,
      target_points: form.targetPoints,
      elimination_rounds: form.eliminationRounds,
      questions_per_round: form.questionsPerRound,
      wrong_answer_penalty: form.wrongPenalty,
      recovery_points: form.recoveryPoints,
      question_time_limit_seconds: form.timeLimit,
      max_consecutive_questions: form.maxConsecutiveQuestions,
    }).select('id,starting_points').single();

    setBusy(false);

    if (error) {
      setWizardNotice(error.message);
      return;
    }

    if (data?.id && uniqueNames.length > 0) {
      const { error: memberError } = await supabase.from('game_members').insert(
        uniqueNames.map((name, index) => ({
          game_id: data.id,
          display_name: name,
          points: data.starting_points,
          turn_order: index + 1,
        })),
      );

      if (memberError) {
        setWizardNotice(memberError.message);
        return;
      }
    }

    if (data?.id && includeHostAsPlayer) {
      const { error: hostError } = await supabase.rpc('add_host_as_player', { p_game_id: data.id });

      if (hostError) {
        setWizardNotice(hostError.message);
        return;
      }
    }

    setForm((current) => ({ ...defaultForm, questionPackId: current.questionPackId }));
    setMemberNames('');
    setIncludeHostAsPlayer(false);
    setWizardOpen(false);
    setWizardStep(1);
    setWizardNotice('');
    showToast('Game created.');
    if (data?.id) setSelectedGameId(data.id);
    await loadDashboard();
  }

  async function addMembers(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedGame) {
      setMemberNotice('Create or select a game first.');
      return;
    }

    const names = memberNames
      .split(/\n|,/)
      .map((name) => name.trim())
      .filter(Boolean);

    if (names.length === 0) {
      setMemberNotice('Add at least one member name.');
      return;
    }

    const existingNames = new Set(members.map((member) => member.display_name.toLowerCase()));
    const uniqueNames = [...new Set(names)].filter((name) => !existingNames.has(name.toLowerCase()));

    if (uniqueNames.length === 0) {
      setMemberNotice('Those members are already on this game.');
      return;
    }

    const remainingSlots = maxPlayersPerGame - members.length;
    if (remainingSlots <= 0) {
      setMemberNotice(`${planLabel} supports up to ${maxPlayersPerGame} players per game.`);
      return;
    }

    if (uniqueNames.length > remainingSlots) {
      setMemberNotice(`You can add ${remainingSlots} more player${remainingSlots === 1 ? '' : 's'} on ${planLabel}.`);
      return;
    }

    setMemberBusy(true);
    setMemberNotice('');

    const nextOrder = members.length + 1;
    const { error } = await supabase.from('game_members').insert(
      uniqueNames.map((name, index) => ({
        game_id: selectedGame.id,
        display_name: name,
        points: selectedGame.starting_points,
        turn_order: nextOrder + index,
      })),
    );

    setMemberBusy(false);

    if (error) {
      setMemberNotice(error.message);
      return;
    }

    setMemberNames('');
    showToast(`${uniqueNames.length} player${uniqueNames.length === 1 ? '' : 's'} added.`);
    await loadMembers(selectedGame.id);
  }

  async function addHostAsPlayer() {
    if (!selectedGame) {
      setMemberNotice('Select a game first.');
      return;
    }

    if (members.length >= maxPlayersPerGame) {
      setMemberNotice(`${planLabel} supports up to ${maxPlayersPerGame} players per game.`);
      return;
    }

    setMemberBusy(true);
    setMemberNotice('');

    const { error } = await supabase.rpc('add_host_as_player', { p_game_id: selectedGame.id });

    setMemberBusy(false);

    if (error) {
      setMemberNotice(error.message);
      return;
    }

    showToast('You joined as a player.');
    await loadMembers(selectedGame.id);
  }

  async function deleteGame(game: Game) {
    if (game.status === 'active') {
      showToast('Cancel the active game before deleting it.', 'error');
      return;
    }

    setConfirmDialog({
      title: 'Delete game?',
      message: `Delete "${game.name}" and all of its players and history? This cannot be undone.`,
      confirmLabel: 'Delete game',
      tone: 'danger',
      onConfirm: () => performDeleteGame(game),
    });
  }

  async function performDeleteGame(game: Game) {
    setGameActionBusy(game.id);
    setNotice('');
    setMemberNotice('');

    const { error } = await supabase.from('games').delete().eq('id', game.id);

    setGameActionBusy('');

    if (error) {
      showToast(error.message, 'error');
      return;
    }

    setMembers([]);
    setSelectedGameId((current) => (current === game.id ? '' : current));
    showToast('Game deleted.');
    await loadDashboard();
  }

  async function cancelGame(game: Game) {
    if (game.status !== 'active') {
      showToast('Only active games need cancelling.', 'error');
      return;
    }

    setConfirmDialog({
      title: 'Cancel live game?',
      message: `Cancel "${game.name}"? Players will be removed from the live round and the game can be deleted afterwards.`,
      confirmLabel: 'Cancel game',
      tone: 'danger',
      onConfirm: () => performCancelGame(game),
    });
  }

  async function performCancelGame(game: Game) {
    setGameActionBusy(game.id);
    setNotice('');
    setMemberNotice('');

    const { error } = await supabase
      .from('games')
      .update({
        status: 'cancelled',
        current_member_id: null,
        current_question_id: null,
        timer_ends_at: null,
        finished_at: new Date().toISOString(),
      })
      .eq('id', game.id);

    setGameActionBusy('');

    if (error) {
      showToast(error.message, 'error');
      return;
    }

    showToast('Game cancelled.');
    await Promise.all([loadDashboard(), loadMembers(game.id)]);
  }

  function startEditingMember(member: GameMember) {
    setEditingMemberId(member.id);
    setMemberDrafts((current) => ({
      ...current,
      [member.id]: {
        display_name: member.display_name,
        points: member.points,
        turn_order: member.turn_order,
      },
    }));
  }

  function updateMemberDraft(memberId: string, patch: Partial<MemberDraft>) {
    setMemberDrafts((current) => ({
      ...current,
      [memberId]: {
        ...(current[memberId] || { display_name: '', points: 0, turn_order: 0 }),
        ...patch,
      },
    }));
  }

  async function saveMember(member: GameMember) {
    if (!selectedGame) return;

    const draft = memberDrafts[member.id];

    if (!draft?.display_name.trim()) {
      setMemberNotice('Player name is required.');
      return;
    }

    setMemberActionBusy(member.id);
    setMemberNotice('');

    const { error } = await supabase
      .from('game_members')
      .update({
        display_name: draft.display_name.trim(),
        points: Math.max(0, Number(draft.points)),
        turn_order: Math.max(1, Number(draft.turn_order)),
      })
      .eq('id', member.id)
      .eq('game_id', selectedGame.id);

    setMemberActionBusy('');

    if (error) {
      setMemberNotice(error.message);
      return;
    }

    setEditingMemberId('');
    showToast('Player updated.');
    await loadMembers(selectedGame.id);
  }

  async function removeMember(member: GameMember) {
    if (!selectedGame) return;

    const game = selectedGame;

    setConfirmDialog({
      title: 'Remove player?',
      message: `Remove ${member.display_name} from "${game.name}"? They will no longer be able to join with this invite.`,
      confirmLabel: 'Remove player',
      tone: 'danger',
      onConfirm: () => performRemoveMember(game, member),
    });
  }

  async function performRemoveMember(game: Game, member: GameMember) {
    setMemberActionBusy(member.id);
    setMemberNotice('');

    const { error } = await supabase.from('game_members').delete().eq('id', member.id).eq('game_id', game.id);

    setMemberActionBusy('');

    if (error) {
      showToast(error.message, 'error');
      return;
    }

    showToast('Player removed.');
    await loadMembers(game.id);
  }

  async function saveGameSettings(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedGame || !gameSettingsDraft) return;

    if (!gameSettingsDraft.name.trim() || !gameSettingsDraft.question_pack_id) {
      setMemberNotice('Game name and question pack are required.');
      return;
    }

    if (isProGameMode(gameSettingsDraft.game_mode) && !canUseProModes) {
      setMemberNotice('Upgrade to Pro to use Speed Round or Elimination Ladder.');
      return;
    }

    if (gameSettingsDraft.game_mode === 'classic' && Number(gameSettingsDraft.target_points) <= Number(gameSettingsDraft.starting_points)) {
      setMemberNotice('Classic winning score must be higher than the starting points.');
      return;
    }

    setGameSettingsBusy(true);
    setMemberNotice('');
    setNotice('');

    const patch = {
      name: gameSettingsDraft.name.trim(),
      game_mode: gameSettingsDraft.game_mode,
      question_pack_id: gameSettingsDraft.question_pack_id,
      starting_points: Math.max(0, Number(gameSettingsDraft.starting_points)),
      target_points: Math.max(1, Number(gameSettingsDraft.target_points)),
      elimination_rounds: Math.max(1, Number(gameSettingsDraft.elimination_rounds)),
      questions_per_round: Math.max(1, Number(gameSettingsDraft.questions_per_round)),
      wrong_answer_penalty: Math.max(0, Number(gameSettingsDraft.wrong_answer_penalty)),
      recovery_points: Math.max(0, Number(gameSettingsDraft.recovery_points)),
      question_time_limit_seconds: Math.max(5, Number(gameSettingsDraft.question_time_limit_seconds)),
      max_consecutive_questions: Math.max(1, Number(gameSettingsDraft.max_consecutive_questions)),
    };

    const { error } = await supabase.from('games').update(patch).eq('id', selectedGame.id).in('status', ['draft', 'lobby']);

    if (error) {
      setGameSettingsBusy(false);
      setMemberNotice(error.message);
      return;
    }

    if (patch.starting_points !== selectedGame.starting_points) {
      const { error: pointsError } = await supabase
        .from('game_members')
        .update({ points: patch.starting_points })
        .eq('game_id', selectedGame.id);

      if (pointsError) {
        setGameSettingsBusy(false);
        setMemberNotice(pointsError.message);
        return;
      }
    }

    setGameSettingsBusy(false);
    showToast('Game settings saved.');
    await Promise.all([loadDashboard(), loadMembers(selectedGame.id)]);
  }

  async function startSelectedGame() {
    if (!selectedGame) {
      setMemberNotice('Select a game first.');
      return;
    }

    setStartBusy(true);
    setMemberNotice('');

    const { error } = await supabase.rpc('start_game', { p_game_id: selectedGame.id });

    setStartBusy(false);

    if (error) {
      setMemberNotice(error.message);
      return;
    }

    showToast('Game started.');
    await Promise.all([loadDashboard(), loadMembers(selectedGame.id)]);
    setManageDrawerOpen(false);
    setControlRoomGame({ ...selectedGame, status: 'active' });
  }

  async function startGameFromTable(game: Game) {
    setSelectedGameId(game.id);
    setStartBusy(true);
    setNotice('');

    const { error } = await supabase.rpc('start_game', { p_game_id: game.id });

    setStartBusy(false);

    if (error) {
      setNotice(error.message);
      return;
    }

    showToast('Game started.');
    await loadDashboard();
    setControlRoomGame({ ...game, status: 'active' });
  }

  async function signOut() {
    setAccountMenuOpen(false);
    await supabase.auth.signOut();
  }

  function openUpgradeModal() {
    setUpgradeOpen(true);
    setAccountMenuOpen(false);
  }

  async function simulateCheckout(planId: Exclude<PlanId, 'free'>, billingInterval: BillingInterval) {
    setPlanActionBusy(planId);

    const { data, error } = await supabase.rpc('set_test_subscription_checkout', {
      p_plan_id: planId,
      p_billing_interval: billingInterval,
    });

    setPlanActionBusy('');

    if (error) {
      showToast(error.message, 'error');
      return;
    }

    if (data) setSubscription(data as Subscription);
    setUpgradeOpen(false);
    setActiveView('games');
    showToast(`You are now on the ${getPlanLabel(planId)}.`);
    await loadDashboard();
  }

  async function saveAccountName() {
    const nextName = accountNameDraft.trim();

    if (!nextName) {
      showToast('Add a display name first.', 'error');
      return;
    }

    setAccountBusy(true);

    const { error } = await supabase.rpc('update_host_display_name', { p_display_name: nextName });

    setAccountBusy(false);

    if (error) {
      showToast(error.message, 'error');
      return;
    }

    setProfile((current) => (current ? { ...current, display_name: nextName } : current));
    showToast('Display name updated.');
    await loadDashboard();
  }

  async function changePassword(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (newPassword.length < 6) {
      showToast('Password must be at least 6 characters.', 'error');
      return;
    }

    if (newPassword !== confirmPassword) {
      showToast('Passwords do not match.', 'error');
      return;
    }

    setPasswordBusy(true);

    const { error } = await supabase.auth.updateUser({ password: newPassword });

    setPasswordBusy(false);

    if (error) {
      showToast(error.message, 'error');
      return;
    }

    setNewPassword('');
    setConfirmPassword('');
    showToast('Password updated.');
  }

  return (
    <main className={`dashboard ${controlRoomGame ? 'game-open' : ''}`}>
      <header className="topbar">
        <div className="brand-row">
          <div className="brand-mark small">
            <LogoMark size={26} />
          </div>
          <span>Quizo</span>
        </div>
        <div className="account-area">
          <span className="plan-badge">{planLabel}</span>
          {currentPlanId !== 'creator' && (
            <button className="topbar-upgrade-button" onClick={openUpgradeModal} type="button">
              Upgrade
            </button>
          )}
          <div className="account-menu">
            <button
              className="account-trigger"
              onClick={() => setAccountMenuOpen((current) => !current)}
              type="button"
              aria-expanded={accountMenuOpen}
              aria-haspopup="menu"
              aria-label="Open account menu"
              title="Account"
            >
              <span className="account-avatar">{accountInitials || <User size={18} />}</span>
            </button>

            {accountMenuOpen && (
              <div className="account-dropdown" role="menu">
                <div className="account-summary">
                  <span className="account-avatar large">{accountInitials || <User size={20} />}</span>
                  <div>
                    <strong>{hostDisplayName}</strong>
                    <span>{accountEmail}</span>
                  </div>
                </div>
                <button
                  className="account-menu-action"
                  onClick={() => {
                    setActiveView('profile');
                    setAccountMenuOpen(false);
                  }}
                  type="button"
                  role="menuitem"
                >
                  <User size={16} />
                  Profile
                </button>
                <button className="account-logout" onClick={signOut} type="button" role="menuitem">
                  <LogOut size={16} />
                  Log out
                </button>
              </div>
            )}
          </div>
        </div>
      </header>

      {activeView === 'profile' ? (
        <ProfileView
          accountBusy={accountBusy}
          accountEmail={accountEmail}
          accountInitials={accountInitials}
          accountNameDraft={accountNameDraft}
          confirmPassword={confirmPassword}
          hostDisplayName={hostDisplayName}
          newPassword={newPassword}
          passwordBusy={passwordBusy}
          planLabel={planLabel}
          subscription={subscription}
          onBack={() => setActiveView('games')}
          onChangePassword={(event) => void changePassword(event)}
          onConfirmPasswordChange={setConfirmPassword}
          onNameChange={setAccountNameDraft}
          onNewPasswordChange={setNewPassword}
          onSaveName={() => void saveAccountName()}
          onUpgrade={openUpgradeModal}
        />
      ) : (
      <section className="game-table-shell">
        <div className="table-toolbar">
          <div>
            <p className="eyebrow">Dashboard</p>
            <h1>Choose how to play</h1>
          </div>
          <div className="table-toolbar-actions">
            <button className="ghost-button table-button toolbar-packs-button" onClick={() => setPacksDrawerOpen(true)} type="button">
              <BookOpen size={18} />
              Packs
            </button>
          </div>
        </div>

        {(notice || memberNotice) && <p className="form-message">{notice || memberNotice}</p>}

        <div className="play-choice-grid" aria-label="Choose play mode">
          <section className="play-choice-card solo">
            <div className="play-choice-icon">
              <CheckCircle2 size={22} />
            </div>
            <div>
              <p className="eyebrow">Single player</p>
              <h2>Play solo</h2>
              <p>Pick a pack, answer at your own pace, then review your score and missed questions.</p>
            </div>
            <button className="primary-button" onClick={() => setPracticeOpen(true)} type="button">
              <Play size={18} />
              Start game
            </button>
          </section>

          <section className="play-choice-card multiplayer">
            <div className="play-choice-icon">
              <UserPlus size={22} />
            </div>
            <div>
              <p className="eyebrow">Multiplayer</p>
              <h2>Host a game</h2>
              <p>Create a live quiz, invite players with a join link, and run the game with a leaderboard.</p>
            </div>
            <button className="primary-button" onClick={openGameWizard} type="button">
              <Plus size={18} />
              Create game
            </button>
          </section>
        </div>

        <AvailablePacksPanel
          canUseCreatorFeatures={canUseCreatorFeatures}
          canUseProPacks={canUseProPacks}
          currentPlanId={currentPlanId}
          open={packsDrawerOpen}
          packQuestionCounts={packQuestionCounts}
          packs={packs}
          planLabel={planLabel}
          onClose={() => setPacksDrawerOpen(false)}
          onUpgrade={openUpgradeModal}
        />

        {dashboardLoading ? (
          <DashboardLoadingState />
        ) : (
          <div className="games-table-stack">
            <div className="games-table-wrap">
              <div className="games-section-heading">
                <div>
                  <p className="eyebrow">Multiplayer</p>
                  <h2>Hosted games</h2>
                </div>
                <span>{activeGames.length} game{activeGames.length === 1 ? '' : 's'}</span>
              </div>
            {games.length === 0 ? (
              <div className="empty-workspace compact-empty">
                <h1>No games yet</h1>
                <p>Create your first game with the Add game button, then invite players from the table.</p>
                <button className="primary-button" onClick={openGameWizard} type="button">
                  <Plus size={18} />
                  Add game
                </button>
              </div>
            ) : activeGames.length === 0 ? (
              <table className="games-table">
                <thead>
                  <tr>
                    <th>Game</th>
                    <th>Status</th>
                    <th>Lobby</th>
                    <th>Join code</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="empty-table-row">
                    <td colSpan={5}>
                      <div className="current-games-empty">
                        <h1>No current games</h1>
                        <p>Create a new game or review finished games below.</p>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            ) : (
              <table className="games-table">
                <thead>
                  <tr>
                    <th>Game</th>
                    <th>Status</th>
                    <th>Lobby</th>
                    <th>Join code</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {activeGames.map((game) => (
                    <GameTableRow
                      key={game.id}
                      game={game}
                      selected={game.id === selectedGameId}
                      playerCount={memberStats[game.id]?.players || 0}
                      joinedCount={memberStats[game.id]?.joined || 0}
                      canStart={(memberStats[game.id]?.joined || 0) >= 2}
                      busy={gameActionBusy === game.id || startBusy}
                      onCancel={() => void cancelGame(game)}
                      onDelete={() => void deleteGame(game)}
                      onSummary={() => void openGameSummary(game)}
                      onManage={() => {
                        setSelectedGameId(game.id);
                        setManageDrawerOpen(true);
                      }}
                      onOpen={() => {
                        setSelectedGameId(game.id);
                        setControlRoomGame(game);
                      }}
                      onStart={() => void startGameFromTable(game)}
                    />
                  ))}
                </tbody>
              </table>
            )}
            </div>

            {completedGames.length > 0 && (
              <div className="games-table-wrap completed-games-wrap">
                <div className="games-section-heading">
                  <div>
                    <p className="eyebrow">History</p>
                    <h2>Completed games</h2>
                  </div>
                  <span>{completedGames.length} game{completedGames.length === 1 ? '' : 's'}</span>
                </div>
                <table className="games-table completed-table">
                  <thead>
                    <tr>
                      <th>Game</th>
                      <th>Status</th>
                      <th>Players</th>
                      <th>Result</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {completedGames.map((game) => (
                      <GameTableRow
                        key={game.id}
                        game={game}
                        selected={game.id === selectedGameId}
                        playerCount={memberStats[game.id]?.players || 0}
                        joinedCount={memberStats[game.id]?.joined || 0}
                        canStart={false}
                        busy={gameActionBusy === game.id}
                        onCancel={() => void cancelGame(game)}
                        onDelete={() => void deleteGame(game)}
                        onSummary={() => void openGameSummary(game)}
                        onManage={() => {
                          setSelectedGameId(game.id);
                          void openGameSummary(game);
                        }}
                        onOpen={() => void openGameSummary(game)}
                        onStart={() => undefined}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            </div>
        )}

        <GameManageDrawer
          canUseProModes={canUseProModes}
          canManage={canManageSelectedGame}
          canStart={canStartSelectedGame}
          draft={gameSettingsDraft}
          game={selectedGame}
          hostMember={hostMember}
          joinedMemberCount={joinedMemberCount}
          maxPlayersPerGame={maxPlayersPerGame}
          memberActionBusy={memberActionBusy}
          memberBusy={memberBusy}
          memberDrafts={memberDrafts}
          memberNames={memberNames}
          memberNotice={memberNotice}
          members={members}
          open={manageDrawerOpen}
          packs={usablePacks}
          saveBusy={gameSettingsBusy}
          selectedJoinUrl={selectedJoinUrl}
          startBusy={startBusy}
          onAddHost={addHostAsPlayer}
          onAddMembers={addMembers}
          onCancelEdit={() => setEditingMemberId('')}
          onClose={() => setManageDrawerOpen(false)}
          onDraftChange={setGameSettingsDraft}
          onEditMember={startEditingMember}
          onMemberDraftChange={updateMemberDraft}
          onMemberNamesChange={setMemberNames}
          onOpenControlRoom={() => selectedGame && setControlRoomGame(selectedGame)}
          onRemoveMember={removeMember}
          onSaveMember={saveMember}
          onSaveSettings={saveGameSettings}
          onStart={startSelectedGame}
          editingMemberId={editingMemberId}
        />

        <GameWizardModal
          busy={busy}
          canUseProModes={canUseProModes}
          form={form}
          hostDisplayName={hostDisplayName}
          includeHostAsPlayer={includeHostAsPlayer}
          maxPlayersPerGame={maxPlayersPerGame}
          memberNames={memberNames}
          notice={wizardNotice}
          open={wizardOpen}
          packQuestionCounts={packQuestionCounts}
          packs={usablePacks}
          setForm={setForm}
          setIncludeHostAsPlayer={setIncludeHostAsPlayer}
          setMemberNames={setMemberNames}
          setStep={setWizardStep}
          step={wizardStep}
          onClose={() => {
            setWizardOpen(false);
            setWizardStep(1);
            setWizardNotice('');
          }}
          onUpgrade={openUpgradeModal}
          onSubmit={() => void createGame()}
        />

        <PracticeModeModal
          currentPlanId={currentPlanId}
          open={practiceOpen}
          packQuestionCounts={packQuestionCounts}
          packs={packs}
          planLabel={planLabel}
          onClose={() => setPracticeOpen(false)}
          onUpgrade={openUpgradeModal}
        />

        <ControlRoomModal game={controlRoomGame} hostMember={hostMember} onClose={() => setControlRoomGame(null)} />
        <GameSummaryModal
          answers={summaryAnswers}
          busy={summaryBusy}
          game={summaryGame}
          members={summaryMembers}
          onClose={() => {
            setSummaryGame(null);
            setSummaryMembers([]);
            setSummaryAnswers([]);
          }}
        />
        <ConfirmActionModal
          dialog={confirmDialog}
          busy={confirmBusy}
          onCancel={() => setConfirmDialog(null)}
          onConfirm={() => void runConfirmedAction()}
        />
      </section>
      )}
      <UpgradeModal
        currentPlanId={currentPlanId}
        busyPlan={planActionBusy}
        open={upgradeOpen}
        onClose={() => setUpgradeOpen(false)}
        onCheckout={(planId, billingInterval) => void simulateCheckout(planId, billingInterval)}
      />
      <Toast toast={toast} onClose={() => setToast(null)} />
    </main>
  );
}

function UpgradeModal({
  busyPlan,
  currentPlanId,
  open,
  onCheckout,
  onClose,
}: {
  busyPlan: PlanId | '';
  currentPlanId: PlanId;
  open: boolean;
  onCheckout: (planId: Exclude<PlanId, 'free'>, billingInterval: BillingInterval) => void;
  onClose: () => void;
}) {
  const [billingInterval, setBillingInterval] = useState<BillingInterval>('monthly');

  if (!open) return null;

  return (
    <div className="modal-backdrop" role="presentation">
      <section className="upgrade-modal" role="dialog" aria-modal="true" aria-labelledby="upgrade-title">
        <div className="upgrade-modal-header">
          <div>
            <p className="eyebrow">Upgrade Quizo</p>
            <h1 id="upgrade-title">Choose your plan</h1>
            <span>This simulates checkout for now. No payment is taken.</span>
          </div>
          <button className="icon-button" onClick={onClose} type="button" aria-label="Close upgrade">
            <X size={18} />
          </button>
        </div>

        <div className="billing-interval-toggle" aria-label="Billing interval">
          {billingIntervals.map((interval) => (
            <button className={billingInterval === interval.id ? 'active' : ''} key={interval.id} onClick={() => setBillingInterval(interval.id)} type="button">
              {interval.label}
            </button>
          ))}
        </div>

        <div className="upgrade-plan-grid">
          {upgradePlans.map((plan) => {
            const isCurrent = currentPlanId === plan.id;
            const isBusy = busyPlan === plan.id;
            const interval = billingIntervals.find((item) => item.id === billingInterval) || billingIntervals[0];

            return (
              <article className={`upgrade-plan-card ${isCurrent ? 'current' : ''}`} key={plan.id}>
                <div>
                  <div className="upgrade-plan-heading">
                    <h2>{planNames[plan.id]}</h2>
                    {isCurrent && <span>Current</span>}
                  </div>
                  <p>{plan.description}</p>
                </div>

                <div className="upgrade-price">
                  <strong>{formatMoney(plan.prices[billingInterval])}</strong>
                  <span>{interval.suffix}</span>
                </div>

                <ul>
                  {plan.features.map((feature) => (
                    <li key={feature}>
                      <CheckCircle2 size={16} />
                      {feature}
                    </li>
                  ))}
                </ul>

                <button className="primary-button" disabled={busyPlan !== '' || isCurrent} onClick={() => onCheckout(plan.id, billingInterval)} type="button">
                  {isBusy ? <RefreshCw className="spin" size={18} /> : <CheckCircle2 size={18} />}
                  {isCurrent ? 'Current plan' : `Upgrade to ${planNames[plan.id]}`}
                </button>
              </article>
            );
          })}
        </div>
      </section>
    </div>
  );
}

function ProfileView({
  accountBusy,
  accountEmail,
  accountInitials,
  accountNameDraft,
  confirmPassword,
  hostDisplayName,
  newPassword,
  passwordBusy,
  planLabel,
  subscription,
  onBack,
  onChangePassword,
  onConfirmPasswordChange,
  onNameChange,
  onNewPasswordChange,
  onSaveName,
  onUpgrade,
}: {
  accountBusy: boolean;
  accountEmail: string;
  accountInitials: React.ReactNode;
  accountNameDraft: string;
  confirmPassword: string;
  hostDisplayName: string;
  newPassword: string;
  passwordBusy: boolean;
  planLabel: string;
  subscription: Subscription | null;
  onBack: () => void;
  onChangePassword: (event: React.FormEvent<HTMLFormElement>) => void;
  onConfirmPasswordChange: (value: string) => void;
  onNameChange: (value: string) => void;
  onNewPasswordChange: (value: string) => void;
  onSaveName: () => void;
  onUpgrade: () => void;
}) {
  const currentPlanId = normalisePlanId(subscription?.plan_id);
  const billingStatus = subscription?.status || 'free';
  const billingInterval = subscription?.billing_interval ? subscription.billing_interval.replace(/_/g, ' ') : 'No paid billing cycle';
  const billingAmount = formatMoney(subscription?.billing_amount_cents, subscription?.currency || 'gbp');

  return (
    <section className="profile-page">
      <div className="profile-toolbar">
        <button className="ghost-button" onClick={onBack} type="button">
          <ArrowLeft size={18} />
          Back to games
        </button>
      </div>

      <div className="profile-hero">
        <div className="profile-avatar">{accountInitials || <User size={28} />}</div>
        <div>
          <p className="eyebrow">Profile</p>
          <h1>{hostDisplayName}</h1>
          <span>{accountEmail}</span>
        </div>
        <span className="plan-badge large">{planLabel}</span>
      </div>

      <div className="profile-grid">
        <section className="profile-card">
          <div className="profile-card-header">
            <div>
              <p className="eyebrow">Account details</p>
              <h2>Your details</h2>
            </div>
            <User size={20} />
          </div>
          <div className="profile-form">
            <label>
              Display name
              <input value={accountNameDraft} onChange={(event) => onNameChange(event.target.value)} minLength={2} required />
            </label>
            <label>
              Email
              <input value={accountEmail} type="email" readOnly />
            </label>
            <button className="primary-button" disabled={accountBusy || accountNameDraft.trim().length < 2} onClick={onSaveName} type="button">
              {accountBusy ? <RefreshCw className="spin" size={18} /> : <Save size={18} />}
              Save details
            </button>
          </div>
        </section>

        <section className="profile-card">
          <div className="profile-card-header">
            <div>
              <p className="eyebrow">Security</p>
              <h2>Change password</h2>
            </div>
            <Lock size={20} />
          </div>
          <form className="profile-form" onSubmit={onChangePassword}>
            <label>
              New password
              <input value={newPassword} onChange={(event) => onNewPasswordChange(event.target.value)} type="password" minLength={6} autoComplete="new-password" />
            </label>
            <label>
              Confirm password
              <input value={confirmPassword} onChange={(event) => onConfirmPasswordChange(event.target.value)} type="password" minLength={6} autoComplete="new-password" />
            </label>
            <button className="primary-button" disabled={passwordBusy || !newPassword || !confirmPassword} type="submit">
              {passwordBusy ? <RefreshCw className="spin" size={18} /> : <Lock size={18} />}
              Update password
            </button>
          </form>
        </section>

        <section className="profile-card billing-card">
          <div className="profile-card-header">
            <div>
              <p className="eyebrow">Subscription</p>
              <h2>Plan and billing</h2>
            </div>
            <span className="plan-badge">{planLabel}</span>
          </div>

          <div className="subscription-detail-list">
            <div>
              <span>Current plan</span>
              <strong>{planNames[currentPlanId]}</strong>
            </div>
            <div>
              <span>Status</span>
              <strong>{billingStatus.replace(/_/g, ' ')}</strong>
            </div>
            <div>
              <span>Next billing date</span>
              <strong>{formatBillingDate(subscription?.current_period_end)}</strong>
            </div>
            <div>
              <span>Billing</span>
              <strong>{billingAmount}</strong>
            </div>
            <div>
              <span>Cycle</span>
              <strong>{billingInterval}</strong>
            </div>
          </div>

          <div className="billing-note">
            <strong>{currentPlanId === 'free' ? 'Ready to upgrade?' : 'Subscription active'}</strong>
            <span>{currentPlanId === 'free' ? 'Choose a paid plan from the upgrade flow when you are ready.' : 'This is simulated billing data for now and will map to Stripe later.'}</span>
            {currentPlanId !== 'creator' && (
              <button className="primary-button compact-button" onClick={onUpgrade} type="button">
                Upgrade plan
              </button>
            )}
          </div>
        </section>
      </div>
    </section>
  );
}

function DashboardLoadingState() {
  return (
    <div className="dashboard-loading-state" role="status" aria-live="polite">
      <section className="games-table-stack loading-panel">
        <div className="games-section-heading">
          <div>
            <p className="eyebrow">Games</p>
            <h2>Loading dashboard</h2>
          </div>
          <LoadingDots />
        </div>
        <div className="skeleton-table">
          {Array.from({ length: 4 }).map((_, index) => (
            <div className="skeleton-row" key={index}>
              <span className="skeleton-dot" />
              <span className="skeleton-line" />
              <span className="skeleton-line tiny" />
              <span className="skeleton-button" />
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

function PracticeModeModal({
  currentPlanId,
  open,
  packs,
  packQuestionCounts,
  planLabel,
  onClose,
  onUpgrade,
}: {
  currentPlanId: PlanId;
  open: boolean;
  packs: QuestionPack[];
  packQuestionCounts: Record<string, number>;
  planLabel: string;
  onClose: () => void;
  onUpgrade: () => void;
}) {
  const canUsePracticePack = (pack: QuestionPack) => pack.tier === 'free' || (pack.tier === 'pro' && currentPlanId !== 'free') || (pack.tier === 'creator' && currentPlanId === 'creator');
  const includedPacks = useMemo(() => packs.filter(canUsePracticePack), [currentPlanId, packs]);
  const [selectedPackId, setSelectedPackId] = useState(includedPacks[0]?.id || '');
  const [questionCount, setQuestionCount] = useState(10);
  const [practiceQuestions, setPracticeQuestions] = useState<PracticeQuestion[]>([]);
  const [answers, setAnswers] = useState<PracticeAnswer[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [visibleResultId, setVisibleResultId] = useState('');

  useEffect(() => {
    if (!includedPacks.length) {
      setSelectedPackId('');
      return;
    }

    if (!includedPacks.some((pack) => pack.id === selectedPackId)) {
      setSelectedPackId(includedPacks[0].id);
    }
  }, [includedPacks, selectedPackId]);

  const selectedPack = includedPacks.find((pack) => pack.id === selectedPackId) || null;
  const availableQuestionCount = selectedPack ? packQuestionCounts[selectedPack.id] || 0 : 0;
  const maxPracticeQuestions = availableQuestionCount;
  const maxSelectableQuestions = Math.min(availableQuestionCount, maxPracticeQuestions);
  const questionOptions = Array.from(new Set([10, 20, 30, 50, 75, 100, maxSelectableQuestions].filter((count) => count > 0 && count <= maxSelectableQuestions))).sort((a, b) => a - b);
  const currentQuestion = practiceQuestions[currentIndex] || null;
  const currentAnswer = currentQuestion ? answers.find((answer) => answer.question.id === currentQuestion.id) || null : null;
  const practiceStarted = practiceQuestions.length > 0;
  const practiceComplete = practiceStarted && currentIndex >= practiceQuestions.length;
  const correctCount = answers.filter((answer) => answer.isCorrect).length;
  const wrongAnswers = answers.filter((answer) => !answer.isCorrect);
  const scorePercent = answers.length ? Math.round((correctCount / answers.length) * 100) : 0;

  useEffect(() => {
    if (maxSelectableQuestions > 0 && questionCount > maxSelectableQuestions) {
      setQuestionCount(maxSelectableQuestions);
    }
  }, [maxSelectableQuestions, questionCount]);

  if (!open) return null;

  function getOptionText(question: PracticeQuestion, option: string) {
    if (option === 'A') return question.option_a;
    if (option === 'B') return question.option_b;
    return question.option_c;
  }

  async function startPractice() {
    if (!selectedPack) {
      setMessage('Choose a question pack first.');
      return;
    }

    if (maxSelectableQuestions <= 0) {
      setMessage('This pack does not have any questions yet.');
      return;
    }

    setLoading(true);
    setMessage('');

    const { data, error } = await supabase
      .from('questions')
      .select('id,prompt,option_a,option_b,option_c,correct_option')
      .eq('pack_id', selectedPack.id);

    setLoading(false);

    if (error) {
      setMessage(error.message);
      return;
    }

    const shuffledQuestions = [...((data || []) as PracticeQuestion[])]
      .sort(() => Math.random() - 0.5)
      .slice(0, Math.min(questionCount, maxSelectableQuestions));

    if (shuffledQuestions.length === 0) {
      setMessage('No questions found for this pack.');
      return;
    }

    setPracticeQuestions(shuffledQuestions);
    setAnswers([]);
    setCurrentIndex(0);
    setVisibleResultId('');
  }

  function chooseAnswer(option: string) {
    if (!currentQuestion || currentAnswer) return;

    const nextAnswer = {
      question: currentQuestion,
      selectedOption: option,
      isCorrect: currentQuestion.correct_option === option,
    };

    setAnswers((current) => [...current, nextAnswer]);
    setVisibleResultId(currentQuestion.id);
  }

  function goNextQuestion() {
    setVisibleResultId('');
    setCurrentIndex((current) => current + 1);
  }

  function resetPractice() {
    setPracticeQuestions([]);
    setAnswers([]);
    setCurrentIndex(0);
    setVisibleResultId('');
    setMessage('');
  }

  function closePractice() {
    resetPractice();
    onClose();
  }

  return (
    <div className="modal-backdrop practice-backdrop" role="dialog" aria-modal="true" aria-label="Solo game">
      <section className="practice-modal">
        <div className="practice-modal-header">
          <div>
            <p className="eyebrow">Single player</p>
            <h2>{practiceStarted ? selectedPack?.name || 'Solo game' : 'Solo game'}</h2>
            <span>Pick a pack, choose a round length, and play through your own quiz.</span>
          </div>
          <div className="practice-modal-actions">
            {practiceStarted && !practiceComplete && (
              <button className="ghost-button table-button" onClick={resetPractice} type="button">
                <ArrowLeft size={17} />
                Setup
              </button>
            )}
            <button className="icon-button neutral" onClick={closePractice} type="button" aria-label="Close solo game" title="Close solo game">
              <X size={18} />
            </button>
          </div>
        </div>

      {!practiceStarted ? (
        <div className="practice-grid">
          <section className="practice-card">
            <div className="profile-card-header">
              <div>
                <p className="eyebrow">Pack</p>
                <h2>Choose questions</h2>
              </div>
              <BookOpen size={22} />
            </div>
            <div className="practice-pack-list">
              {packs.length === 0 ? (
                <p className="empty-state">No packs are available on this plan yet.</p>
              ) : (
                packs.map((pack) => {
                  const included = canUsePracticePack(pack);

                  return (
                    <button
                      className={`practice-pack-button ${selectedPackId === pack.id ? 'selected' : ''} ${included ? 'included' : 'locked'}`}
                      key={pack.id}
                      onClick={() => {
                        if (included) {
                          setSelectedPackId(pack.id);
                          setMessage('');
                        } else {
                          onUpgrade();
                        }
                      }}
                      type="button"
                    >
                      <div>
                        <strong>{pack.name}</strong>
                        <span>{pack.description || 'Solo quiz questions'}</span>
                      </div>
                      <div className="practice-pack-meta">
                        <em>{packQuestionCounts[pack.id] || 0}</em>
                        <b>
                          {included ? (
                            'Included'
                          ) : (
                            <>
                              <Lock size={13} />
                              Upgrade
                            </>
                          )}
                        </b>
                      </div>
                    </button>
                  );
                })
              )}
            </div>
          </section>

          <section className="practice-card">
            <div className="profile-card-header">
              <div>
                <p className="eyebrow">Session</p>
                <h2>Set the length</h2>
              </div>
              <CheckCircle2 size={22} />
            </div>

            <div className="practice-settings">
              <div className="subscription-detail-list practice-stat-list">
                <div>
                  <span>Pack</span>
                  <strong>{availableQuestionCount}</strong>
                </div>
                <div>
                  <span>Max round</span>
                  <strong>{maxPracticeQuestions}</strong>
                </div>
                <div>
                  <span>Selected</span>
                  <strong>{questionCount}</strong>
                </div>
              </div>

              <div className="practice-count-options" aria-label="Choose question count">
                {questionOptions.length === 0 ? (
                  <p className="empty-state">Choose a pack with questions to start.</p>
                ) : (
                  questionOptions.map((count) => (
                    <button className={questionCount === count ? 'active' : ''} key={count} onClick={() => setQuestionCount(count)} type="button">
                      {count}
                    </button>
                  ))
                )}
              </div>

              {currentPlanId === 'free' && (
                <div className="billing-note">
                  <strong>Free solo games can use every question in your included packs.</strong>
                  <span>Upgrade to unlock more packs and more ways to play.</span>
                  <button className="primary-button compact-button" onClick={onUpgrade} type="button">
                    Upgrade
                  </button>
                </div>
              )}

              {message && <p className="form-message">{message}</p>}

              <button className="primary-button" disabled={loading || !selectedPack || maxSelectableQuestions === 0} onClick={() => void startPractice()} type="button">
                {loading ? <RefreshCw className="spin" size={18} /> : <Play size={18} />}
                Start solo game
              </button>
            </div>
          </section>
        </div>
      ) : practiceComplete ? (
        <div className="practice-results">
          <section className="practice-card practice-results-card">
            <div className="profile-card-header">
              <div>
                <p className="eyebrow">Results</p>
                <h2>{wrongAnswers.length ? 'Round complete' : 'Perfect score'}</h2>
              </div>
              <CheckCircle2 size={22} />
            </div>

            <div className="practice-score-strip">
              <div className="practice-score-main">
                <span>Score</span>
                <strong>{correctCount} / {practiceQuestions.length}</strong>
              </div>
              <div className="practice-score-stat">
                <span>Accuracy</span>
                <strong>{scorePercent}%</strong>
              </div>
              <div className="practice-score-stat">
                <span>Review</span>
                <strong>{wrongAnswers.length ? `${wrongAnswers.length} missed` : 'All clear'}</strong>
              </div>
              <button className="primary-button compact-button" onClick={resetPractice} type="button">
                <RefreshCw size={17} />
                New solo game
              </button>
            </div>

            <div className="practice-review-list">
              {(wrongAnswers.length ? wrongAnswers : answers).map((answer, index) => (
                <article className={`practice-review-row ${answer.isCorrect ? 'correct' : 'wrong'}`} key={answer.question.id}>
                  <span>{index + 1}</span>
                  <div>
                    <strong>{answer.question.prompt}</strong>
                    <small>
                      You chose {getOptionText(answer.question, answer.selectedOption)} · Correct answer: {getOptionText(answer.question, answer.question.correct_option)}
                    </small>
                  </div>
                </article>
              ))}
            </div>
          </section>
        </div>
      ) : currentQuestion ? (
        <section className="practice-play-card">
          <div className="practice-progress">
            <span>Question {currentIndex + 1} of {practiceQuestions.length}</span>
            <strong>{selectedPack?.name || 'Practice'}</strong>
          </div>

          <div className="practice-question">
            <h2>{currentQuestion.prompt}</h2>
            <div className="practice-answer-grid">
              {(['A', 'B', 'C'] as const).map((option) => {
                const isSelected = currentAnswer?.selectedOption === option;
                const isCorrectOption = currentAnswer && currentQuestion.correct_option === option;
                const answerState = currentAnswer ? (isCorrectOption ? 'correct' : isSelected ? 'wrong' : 'muted') : '';

                return (
                  <button
                    className={`practice-answer-button ${answerState}`}
                    disabled={Boolean(currentAnswer)}
                    key={option}
                    onClick={() => chooseAnswer(option)}
                    type="button"
                  >
                    <span>{option}</span>
                    {getOptionText(currentQuestion, option)}
                  </button>
                );
              })}
            </div>
          </div>

          {currentAnswer && visibleResultId === currentQuestion.id && (
            <PracticeAnswerPopup
              answer={currentAnswer}
              correctAnswer={getOptionText(currentQuestion, currentQuestion.correct_option)}
              isFinalQuestion={currentIndex + 1 >= practiceQuestions.length}
              onNext={goNextQuestion}
            />
          )}
        </section>
      ) : null}
      </section>
    </div>
  );
}

function PracticeAnswerPopup({
  answer,
  correctAnswer,
  isFinalQuestion,
  onNext,
}: {
  answer: PracticeAnswer;
  correctAnswer: string;
  isFinalQuestion: boolean;
  onNext: () => void;
}) {
  return (
    <div className={`practice-result-popup ${answer.isCorrect ? 'correct' : 'wrong'}`} role="status" aria-live="polite">
      <div className="answer-result-icon">{answer.isCorrect ? <CheckCircle2 size={24} /> : <X size={24} />}</div>
      <div>
        <strong>{answer.isCorrect ? 'Correct' : 'Wrong'}</strong>
        <span>Correct answer: {correctAnswer}</span>
      </div>
      <button className="primary-button compact-button" onClick={onNext} type="button">
        {isFinalQuestion ? 'Show results' : 'Next question'}
      </button>
    </div>
  );
}

function AvailablePacksPanel({
  canUseCreatorFeatures,
  canUseProPacks,
  currentPlanId,
  open,
  packs,
  packQuestionCounts,
  planLabel,
  onClose,
  onUpgrade,
}: {
  canUseCreatorFeatures: boolean;
  canUseProPacks: boolean;
  currentPlanId: PlanId;
  open: boolean;
  packs: QuestionPack[];
  packQuestionCounts: Record<string, number>;
  planLabel: string;
  onClose: () => void;
  onUpgrade: () => void;
}) {
  const [activeTier, setActiveTier] = useState<'all' | 'free' | 'pro' | 'creator'>('all');
  const [packSearch, setPackSearch] = useState('');
  const [selectedPack, setSelectedPack] = useState<QuestionPack | null>(null);
  const isPackIncluded = (pack: QuestionPack) => pack.tier === 'free' || (pack.tier === 'pro' && canUseProPacks) || (pack.tier === 'creator' && canUseCreatorFeatures);
  const tierFilters: Array<{ id: 'all' | 'free' | 'pro' | 'creator'; label: string }> = [
    { id: 'all', label: 'All' },
    { id: 'free', label: 'Free' },
    { id: 'pro', label: 'Pro' },
    { id: 'creator', label: 'Creator' },
  ];
  const filteredPacks = packs.filter((pack) => {
    const matchesTier = activeTier === 'all' || pack.tier === activeTier;
    const searchText = `${pack.name} ${pack.description || ''}`.toLowerCase();
    return matchesTier && searchText.includes(packSearch.trim().toLowerCase());
  });
  const includedCount = packs.filter(isPackIncluded).length;

  if (!open) return null;

  return (
    <div className="pack-drawer-backdrop" onClick={onClose} role="presentation">
      <aside className="pack-drawer" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label="Question packs">
        <div className="pack-drawer-header">
          <div>
            <p className="eyebrow">Question packs</p>
            <h2>Packs</h2>
            <p className="section-helper">{includedCount} of {packs.length} included on {planLabel}.</p>
          </div>
          <button className="icon-button neutral" onClick={onClose} type="button" aria-label="Close packs" title="Close packs">
            <X size={18} />
          </button>
        </div>

        <div className="pack-plan-actions">
          <span className="plan-badge large">{planLabel}</span>
          {currentPlanId === 'free' && (
            <button className="table-button primary-table-button" onClick={onUpgrade} type="button">
              Upgrade
            </button>
          )}
        </div>

        <div className="pack-browser">
          <label className="pack-search">
            <Search size={16} />
            <input value={packSearch} onChange={(event) => setPackSearch(event.target.value)} placeholder="Search packs" type="search" />
          </label>

          <div className="pack-filter-tabs" aria-label="Filter question packs">
            {tierFilters.map((filter) => (
              <button className={activeTier === filter.id ? 'active' : ''} key={filter.id} onClick={() => setActiveTier(filter.id)} type="button">
                {filter.label}
              </button>
            ))}
          </div>

          <div className="pack-compact-list">
            {filteredPacks.length === 0 && <p className="pack-empty-state">No packs match that search.</p>}
            {filteredPacks.map((pack) => {
              const included = isPackIncluded(pack);

              return (
                <button className={`pack-compact-row ${included ? 'included' : 'locked'} ${selectedPack?.id === pack.id ? 'selected' : ''}`} key={pack.id} onClick={() => setSelectedPack(pack)} type="button">
                  <div>
                    <strong>{pack.name}</strong>
                    <span>{pack.description || 'Starter quiz pack'}</span>
                  </div>
                  <div className="pack-card-footer">
                    <em>{packQuestionCounts[pack.id] || 0} questions</em>
                    {included ? (
                      <b>Included</b>
                    ) : (
                      <b>
                        <Lock size={14} />
                        {getPackTierLabel(pack.tier)}
                      </b>
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {selectedPack && (
          <PackDetailsPanel
            included={isPackIncluded(selectedPack)}
            pack={selectedPack}
            questionCount={packQuestionCounts[selectedPack.id] || 0}
            onClear={() => setSelectedPack(null)}
            onUpgrade={onUpgrade}
          />
        )}
      </aside>
    </div>
  );
}

function PackDetailsPanel({
  included,
  pack,
  questionCount,
  onClear,
  onUpgrade,
}: {
  included: boolean;
  pack: QuestionPack;
  questionCount: number;
  onClear: () => void;
  onUpgrade: () => void;
}) {
  return (
      <section className="pack-details-panel" aria-label={`${pack.name} details`}>
        <div className="pack-details-header">
          <div>
            <p className="eyebrow">{getPackTierLabel(pack.tier)} pack</p>
            <h2>{pack.name}</h2>
          </div>
          <button className="icon-button neutral" onClick={onClear} type="button" aria-label="Clear pack details" title="Clear">
            <X size={18} />
          </button>
        </div>
        <p>{pack.description || 'Starter quiz pack'}</p>
        <div className="pack-details-meta">
          <span>{questionCount} questions</span>
          <span>{included ? 'Included' : 'Locked'}</span>
          <span>{getPackTierLabel(pack.tier)}</span>
        </div>
        {!included && (
          <button className="primary-button" onClick={onUpgrade} type="button">
            <Lock size={17} />
            Upgrade to unlock
          </button>
        )}
      </section>
  );
}

function ReadinessItem({ done, label }: { done: boolean; label: string }) {
  return (
    <div className={`readiness-item ${done ? 'done' : ''}`}>
      <CheckCircle2 size={18} />
      <span>{label}</span>
    </div>
  );
}

function Toast({ toast, onClose }: { toast: ToastState | null; onClose: () => void }) {
  if (!toast) return null;

  return (
    <div className={`toast ${toast.tone}`} role="status" aria-live="polite">
      <span>{toast.tone === 'success' ? <CheckCircle2 size={18} /> : <AlertTriangle size={18} />}</span>
      <strong>{toast.message}</strong>
      <button className="toast-close" onClick={onClose} type="button" aria-label="Dismiss message" title="Dismiss message">
        <X size={16} />
      </button>
    </div>
  );
}

function ConfirmActionModal({
  dialog,
  busy,
  onCancel,
  onConfirm,
}: {
  dialog: ConfirmDialogState | null;
  busy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  if (!dialog) return null;

  return (
    <div className="modal-backdrop confirm-backdrop" role="dialog" aria-modal="true" aria-label={dialog.title}>
      <section className="confirm-modal">
        <div className={`confirm-icon ${dialog.tone}`}>
          <AlertTriangle size={24} />
        </div>
        <div>
          <p className="eyebrow">Confirm action</p>
          <h2>{dialog.title}</h2>
          <p>{dialog.message}</p>
        </div>
        <div className="confirm-actions">
          <button className="ghost-button" disabled={busy} onClick={onCancel} type="button">
            Cancel
          </button>
          <button className={`primary-button ${dialog.tone === 'danger' ? 'danger-action' : ''}`} disabled={busy} onClick={onConfirm} type="button">
            {busy ? <RefreshCw className="spin" size={18} /> : <CheckCircle2 size={18} />}
            {dialog.confirmLabel}
          </button>
        </div>
      </section>
    </div>
  );
}

function NumberInput({ label, value, disabled, onChange }: { label: string; value: number; disabled?: boolean; onChange: (value: number) => void }) {
  return (
    <label>
      {label}
      <input value={value} onChange={(event) => onChange(Number(event.target.value))} type="number" min={0} required disabled={disabled} />
    </label>
  );
}

function CopyButton({ value, label, variant = 'icon' }: { value: string; label: string; variant?: 'icon' | 'label' }) {
  const [copied, setCopied] = useState(false);

  async function copyValue() {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2200);
  }

  return (
    <button
      className={`${variant === 'label' ? 'copy-link-button' : 'icon-button copy-icon-button'} ${copied ? 'copied' : ''}`}
      onClick={copyValue}
      type="button"
      aria-label={copied ? 'Copied join link' : label}
      title={copied ? 'Copied' : label}
    >
      {copied ? <CheckCircle2 size={16} /> : <Clipboard size={16} />}
      {variant === 'label' && <span>{copied ? 'Copied' : 'Copy link'}</span>}
      {variant === 'icon' && copied && <span className="copy-confirm">Copied</span>}
    </button>
  );
}

function GameTableRow({
  game,
  selected,
  playerCount,
  joinedCount,
  canStart,
  busy,
  onCancel,
  onDelete,
  onManage,
  onOpen,
  onSummary,
  onStart,
}: {
  game: Game;
  selected: boolean;
  playerCount?: number;
  joinedCount?: number;
  canStart: boolean;
  busy: boolean;
  onCancel: () => void;
  onDelete: () => void;
  onManage: () => void;
  onOpen: () => void;
  onSummary: () => void;
  onStart: () => void;
}) {
  const joinUrl = getJoinUrl(game.join_code);
  const created = new Intl.DateTimeFormat(undefined, { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(game.created_at));
  const totalPlayers = playerCount ?? 0;
  const joinedPlayers = joinedCount ?? 0;
  const waitingPlayers = Math.max(0, totalPlayers - joinedPlayers);
  const isCompletedGame = ['finished', 'cancelled'].includes(game.status);

  return (
    <tr className={selected ? 'selected' : ''}>
      <td>
        <strong>{game.name}</strong>
        <span className="table-subline">
          {getGameModeLabel(game.game_mode)} · Created {created}
        </span>
      </td>
      <td>
        <span className={`status-pill ${game.status}`}>{game.status}</span>
      </td>
      <td>
        {isCompletedGame ? (
          <div className="final-player-state">
            <strong>{totalPlayers || '-'}</strong>
            <span>final players</span>
          </div>
        ) : (
          <>
            <div className="lobby-state">
              <strong>{joinedPlayers}/{totalPlayers || '-'}</strong>
              <span>joined</span>
            </div>
            <div className="lobby-breakdown">
              <span className="joined">{joinedPlayers} in lobby</span>
              <span className="waiting">{waitingPlayers} waiting</span>
            </div>
          </>
        )}
      </td>
      <td>
        {isCompletedGame ? (
          <div className="result-state">
            <strong>{game.status === 'finished' ? 'Summary ready' : 'Cancelled'}</strong>
            <span>{game.status === 'finished' ? 'Final places saved' : 'No join link needed'}</span>
          </div>
        ) : (
          <div className="table-code">
            <span>{game.join_code}</span>
            <CopyButton value={joinUrl} label="Copy join link" />
          </div>
        )}
      </td>
      <td>
        <div className="row-actions">
          {['finished', 'cancelled'].includes(game.status) ? (
            <>
              <button className="primary-button table-button" onClick={onSummary} type="button">
                <CheckCircle2 size={16} />
                Summary
              </button>
              <button className="icon-button danger" disabled={busy} onClick={onDelete} type="button" aria-label="Delete game" title="Delete game">
                {busy ? <RefreshCw className="spin" size={18} /> : <Trash2 size={18} />}
              </button>
            </>
          ) : game.status === 'active' ? (
            <>
              <button className="primary-button table-button" onClick={onOpen} type="button">
                <Play size={16} />
                Open
              </button>
              <button className="icon-button danger" disabled={busy} onClick={onCancel} type="button" aria-label="Cancel game" title="Cancel game">
                {busy ? <RefreshCw className="spin" size={18} /> : <X size={18} />}
              </button>
            </>
          ) : (
            <>
              <button className="ghost-button table-button" onClick={onManage} type="button">
                <Pencil size={16} />
                Edit
              </button>
              {['draft', 'lobby'].includes(game.status) && (
                <button className="primary-button table-button" disabled={busy || !canStart} onClick={onStart} type="button">
                  {busy ? <RefreshCw className="spin" size={16} /> : <Play size={16} />}
                  Start
                </button>
              )}
              <button className="icon-button danger" disabled={busy} onClick={onDelete} type="button" aria-label="Delete game" title="Delete game">
                {busy ? <RefreshCw className="spin" size={18} /> : <Trash2 size={18} />}
              </button>
            </>
          )}
        </div>
      </td>
    </tr>
  );
}

function GameManageDrawer({
  open,
  game,
  draft,
  packs,
  canUseProModes,
  members,
  memberNames,
  memberNotice,
  hostMember,
  memberDrafts,
  editingMemberId,
  canManage,
  canStart,
  joinedMemberCount,
  maxPlayersPerGame,
  selectedJoinUrl,
  memberBusy,
  memberActionBusy,
  saveBusy,
  startBusy,
  onClose,
  onDraftChange,
  onSaveSettings,
  onAddMembers,
  onMemberNamesChange,
  onAddHost,
  onEditMember,
  onMemberDraftChange,
  onCancelEdit,
  onRemoveMember,
  onSaveMember,
  onStart,
  onOpenControlRoom,
}: {
  open: boolean;
  game: Game | null;
  draft: GameSettingsDraft | null;
  packs: QuestionPack[];
  canUseProModes: boolean;
  members: GameMember[];
  memberNames: string;
  memberNotice: string;
  hostMember: GameMember | null;
  memberDrafts: Record<string, MemberDraft>;
  editingMemberId: string;
  canManage: boolean;
  canStart: boolean;
  joinedMemberCount: number;
  maxPlayersPerGame: number;
  selectedJoinUrl: string;
  memberBusy: boolean;
  memberActionBusy: string;
  saveBusy: boolean;
  startBusy: boolean;
  onClose: () => void;
  onDraftChange: React.Dispatch<React.SetStateAction<GameSettingsDraft | null>>;
  onSaveSettings: (event: React.FormEvent<HTMLFormElement>) => void;
  onAddMembers: (event: React.FormEvent<HTMLFormElement>) => void;
  onMemberNamesChange: React.Dispatch<React.SetStateAction<string>>;
  onAddHost: () => void;
  onEditMember: (member: GameMember) => void;
  onMemberDraftChange: (memberId: string, patch: Partial<MemberDraft>) => void;
  onCancelEdit: () => void;
  onRemoveMember: (member: GameMember) => void;
  onSaveMember: (member: GameMember) => void;
  onStart: () => void;
  onOpenControlRoom: () => void;
}) {
  const [renderDrawer, setRenderDrawer] = useState(open);

  useEffect(() => {
    if (open) {
      setRenderDrawer(true);
      return undefined;
    }

    const closeTimer = window.setTimeout(() => setRenderDrawer(false), 240);
    return () => window.clearTimeout(closeTimer);
  }, [open]);

  if (!renderDrawer || !game || !draft) return null;

  const updateDraft = (patch: Partial<GameSettingsDraft>) => {
    onDraftChange((current) => (current ? { ...current, ...patch } : current));
  };
  const proModeLocked = isProGameMode(draft.game_mode) && !canUseProModes;
  const joinedMembers = members.filter((member) => ['joined', 'active'].includes(member.status));
  const waitingMembers = members.filter((member) => member.status === 'invited');
  const inactiveMembers = members.filter((member) => !['active', 'invited', 'joined'].includes(member.status));
  const readyLabel = canStart ? 'Ready to start' : members.length === 0 ? 'Add players' : `${Math.max(0, 2 - joinedMemberCount)} more to join`;
  const playerLimitReached = members.length >= maxPlayersPerGame;

  return (
    <div
      className={`drawer-backdrop ${open ? 'open' : 'closing'}`}
      role="dialog"
      aria-modal="true"
      aria-label="Edit game"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <aside className={`game-drawer ${open ? 'open' : 'closing'}`}>
        <div className="drawer-header">
          <div>
            <p className="eyebrow">Edit game</p>
            <h2>{game.name}</h2>
            <div className="workspace-meta">
              <span className={`status-pill ${game.status}`}>{game.status}</span>
              <span>{members.length} player{members.length === 1 ? '' : 's'}</span>
              <span>{maxPlayersPerGame} max</span>
              <span>{joinedMemberCount} joined</span>
            </div>
          </div>
          <button className="icon-button neutral" onClick={onClose} type="button" aria-label="Close drawer" title="Close drawer">
            <X size={18} />
          </button>
        </div>

        <div className="drawer-content">
          <section className="drawer-section">
            <div className="section-heading">
              <div>
                <p className="eyebrow">Share</p>
                <h2>Join details</h2>
                <p className="section-helper">Copy this join link and send it to each player. They can open the link or enter the code to join the lobby.</p>
              </div>
              <div className="join-code share-code">
                <span>{game.join_code}</span>
                <CopyButton value={selectedJoinUrl} label="Copy join link" variant="label" />
              </div>
            </div>
            <div className="setup-strip">
              <ReadinessItem done={Boolean(game.join_code)} label="Join code ready" />
              <ReadinessItem done={members.length > 0} label={`${members.length}/${maxPlayersPerGame} added`} />
              <ReadinessItem done={joinedMemberCount >= 2} label={`${joinedMemberCount} joined`} />
            </div>
            <div className="lobby-readiness">
              <div className={`readiness-summary ${canStart ? 'ready' : ''}`}>
                <span>Lobby status</span>
                <strong>{readyLabel}</strong>
              </div>
              <div className="lobby-progress" aria-label={`${joinedMemberCount} of ${members.length} players joined`}>
                <span style={{ width: `${members.length ? Math.round((joinedMemberCount / members.length) * 100) : 0}%` }} />
              </div>
              <div className="lobby-stats-grid">
                <div>
                  <span>Joined</span>
                  <strong>{joinedMemberCount}</strong>
                </div>
                <div>
                  <span>Waiting</span>
                  <strong>{waitingMembers.length}</strong>
                </div>
                <div>
                  <span>Total</span>
                  <strong>{members.length}</strong>
                </div>
              </div>
            </div>
          </section>

          <form className="drawer-section" onSubmit={onSaveSettings}>
            <div className="section-heading">
              <div>
                <p className="eyebrow">Rules</p>
                <h2>Game settings</h2>
              </div>
              <button className="primary-button table-button" disabled={saveBusy || !canManage} type="submit">
                {saveBusy ? <RefreshCw className="spin" size={16} /> : <Save size={16} />}
                Save
              </button>
            </div>

            <div className="form-grid">
              <label className="wide">
                Game name
                <input value={draft.name} onChange={(event) => updateDraft({ name: event.target.value })} disabled={!canManage} />
              </label>
              <label className="wide">
                Question pack
                <select value={draft.question_pack_id} onChange={(event) => updateDraft({ question_pack_id: event.target.value })} disabled={!canManage}>
                  {packs.map((pack) => (
                    <option key={pack.id} value={pack.id}>
                      {pack.name} ({pack.tier})
                    </option>
                  ))}
                </select>
              </label>
              <label className="wide">
                Game mode
                <select
                  value={draft.game_mode}
                  onChange={(event) => {
                    const nextMode = event.target.value;
                    updateDraft({
                      game_mode: nextMode,
                      starting_points: nextMode === 'race_to_points' || nextMode === 'speed_round' ? 0 : draft.starting_points || 100,
                      target_points:
                        nextMode === 'classic'
                          ? draft.target_points > (draft.starting_points || 100)
                            ? draft.target_points
                            : (draft.starting_points || 100) + 50
                          : nextMode === 'race_to_points' || nextMode === 'speed_round'
                            ? draft.target_points || 100
                            : draft.target_points,
                    });
                  }}
                  disabled={!canManage}
                >
                  <option value="classic">Classic last player standing</option>
                  <option value="race_to_points">Race to points</option>
                  <option value="speed_round" disabled={!canUseProModes}>
                    Speed round (Pro)
                  </option>
                  <option value="elimination_ladder" disabled={!canUseProModes}>
                    Elimination ladder (Pro)
                  </option>
                </select>
                {proModeLocked && <span className="field-hint">Upgrade to Pro to save this game mode.</span>}
              </label>
              <NumberInput label="Starting points" value={draft.starting_points} disabled={!canManage} onChange={(value) => updateDraft({ starting_points: value })} />
              {(draft.game_mode === 'classic' || draft.game_mode === 'race_to_points' || draft.game_mode === 'speed_round') && <NumberInput label={draft.game_mode === 'classic' ? 'Winning score' : 'Target points'} value={draft.target_points} disabled={!canManage} onChange={(value) => updateDraft({ target_points: value })} />}
              {draft.game_mode === 'elimination_ladder' && <NumberInput label="Ladder rounds" value={draft.elimination_rounds} disabled={!canManage} onChange={(value) => updateDraft({ elimination_rounds: value })} />}
              {draft.game_mode === 'elimination_ladder' && <NumberInput label="Questions/round" value={draft.questions_per_round} disabled={!canManage} onChange={(value) => updateDraft({ questions_per_round: value })} />}
              <NumberInput label="Wrong penalty" value={draft.wrong_answer_penalty} disabled={!canManage} onChange={(value) => updateDraft({ wrong_answer_penalty: value })} />
              <NumberInput label="Correct points" value={draft.recovery_points} disabled={!canManage} onChange={(value) => updateDraft({ recovery_points: value })} />
              <NumberInput
                label="Seconds/question"
                value={draft.question_time_limit_seconds}
                disabled={!canManage}
                onChange={(value) => updateDraft({ question_time_limit_seconds: value })}
              />
              <NumberInput
                label="Questions/turn"
                value={draft.max_consecutive_questions}
                disabled={!canManage || draft.game_mode === 'speed_round' || draft.game_mode === 'elimination_ladder'}
                onChange={(value) => updateDraft({ max_consecutive_questions: value })}
              />
            </div>
            {!canManage && <p className="empty-state">Settings can only be edited before the game starts.</p>}
          </form>

          <section className="drawer-section">
            <div className="section-heading">
              <div>
                <p className="eyebrow">Players</p>
                <h2>Lobby players</h2>
                <p className="section-helper">{members.length} of {maxPlayersPerGame} player slots used.</p>
              </div>
              {!hostMember && canManage && (
                <button className="ghost-button table-button" disabled={memberBusy || playerLimitReached} onClick={onAddHost} type="button">
                  <UserPlus size={16} />
                  Add me
                </button>
              )}
            </div>

            {hostMember && <p className="host-player-note">You are playing as {hostMember.display_name}.</p>}

            <form className="add-player-bar" onSubmit={onAddMembers}>
              <label>
                Add player names
                <textarea
                  value={memberNames}
                  onChange={(event) => onMemberNamesChange(event.target.value)}
                  placeholder={'Sarah\nJames\nPriya'}
                  rows={3}
                  disabled={!canManage || playerLimitReached}
                />
              </label>
              <button className="primary-button" disabled={memberBusy || !canManage || playerLimitReached} type="submit">
                {memberBusy ? <RefreshCw className="spin" size={18} /> : <UserPlus size={18} />}
                Add
              </button>
            </form>

            {playerLimitReached && <p className="field-hint">This game has reached the player limit for your current plan.</p>}
            {memberNotice && <p className="form-message">{memberNotice}</p>}

            <div className="member-list grouped">
              {members.length === 0 ? (
                <p className="empty-state">No members added yet.</p>
              ) : (
                <>
                  <MemberGroup
                    title="In lobby"
                    empty="No players have joined yet."
                    members={joinedMembers}
                    memberDrafts={memberDrafts}
                    editingMemberId={editingMemberId}
                    memberActionBusy={memberActionBusy}
                    disabled={!canManage}
                    onCancelEdit={onCancelEdit}
                    onEditMember={onEditMember}
                    onMemberDraftChange={onMemberDraftChange}
                    onRemoveMember={onRemoveMember}
                    onSaveMember={onSaveMember}
                  />
                  <MemberGroup
                    title="Waiting"
                    empty="Everyone has joined."
                    members={waitingMembers}
                    memberDrafts={memberDrafts}
                    editingMemberId={editingMemberId}
                    memberActionBusy={memberActionBusy}
                    disabled={!canManage}
                    onCancelEdit={onCancelEdit}
                    onEditMember={onEditMember}
                    onMemberDraftChange={onMemberDraftChange}
                    onRemoveMember={onRemoveMember}
                    onSaveMember={onSaveMember}
                  />
                  {inactiveMembers.length > 0 && (
                    <MemberGroup
                      title="Inactive"
                      empty=""
                      members={inactiveMembers}
                      memberDrafts={memberDrafts}
                      editingMemberId={editingMemberId}
                      memberActionBusy={memberActionBusy}
                      disabled={!canManage}
                      onCancelEdit={onCancelEdit}
                      onEditMember={onEditMember}
                      onMemberDraftChange={onMemberDraftChange}
                      onRemoveMember={onRemoveMember}
                      onSaveMember={onSaveMember}
                    />
                  )}
                </>
              )}
            </div>
          </section>
        </div>

        <div className="drawer-footer">
          {game.status === 'active' ? (
            <button className="primary-button" onClick={onOpenControlRoom} type="button">
              <Play size={18} />
              Open control room
            </button>
          ) : (
            <>
              <button className="primary-button" disabled={startBusy || !canStart} onClick={onStart} type="button">
                {startBusy ? <RefreshCw className="spin" size={18} /> : <Play size={18} />}
                Start game
              </button>
              {!canStart && canManage && <p className="empty-state">At least two members need to join before the game can start.</p>}
            </>
          )}
        </div>
      </aside>
    </div>
  );
}

function GameWizardModal({
  open,
  step,
  form,
  packs,
  packQuestionCounts,
  canUseProModes,
  hostDisplayName,
  includeHostAsPlayer,
  maxPlayersPerGame,
  memberNames,
  busy,
  notice,
  setStep,
  setForm,
  setIncludeHostAsPlayer,
  setMemberNames,
  onClose,
  onUpgrade,
  onSubmit,
}: {
  open: boolean;
  step: number;
  form: typeof defaultForm;
  packs: QuestionPack[];
  packQuestionCounts: Record<string, number>;
  canUseProModes: boolean;
  hostDisplayName: string;
  includeHostAsPlayer: boolean;
  maxPlayersPerGame: number;
  memberNames: string;
  busy: boolean;
  notice: string;
  setStep: React.Dispatch<React.SetStateAction<number>>;
  setForm: React.Dispatch<React.SetStateAction<typeof defaultForm>>;
  setIncludeHostAsPlayer: React.Dispatch<React.SetStateAction<boolean>>;
  setMemberNames: React.Dispatch<React.SetStateAction<string>>;
  onClose: () => void;
  onUpgrade: () => void;
  onSubmit: () => void;
}) {
  const [playerNameDraft, setPlayerNameDraft] = useState('');

  if (!open) return null;

  const steps = ['Basics', 'Rules', 'Players', 'Review'];
  const modeDetails: Record<GameMode, { title: string; badge: string; description: string; helper: string }> = {
    classic: {
      title: 'Classic',
      badge: 'Free',
      description: 'Turn-based quiz with points and knockouts.',
      helper: 'Players start with points. Correct answers build toward the winning score, wrong answers cost points, and play moves on.',
    },
    race_to_points: {
      title: 'Race to Points',
      badge: 'Free',
      description: 'Take turns racing from zero to a target.',
      helper: 'Correct answers push players toward the target. Wrong answers pull them back and keep the pressure on.',
    },
    speed_round: {
      title: 'Speed Round',
      badge: 'Pro',
      description: 'Everyone sees the same question at once.',
      helper: 'The first player to answer takes control. If they miss, they get one locked-in second chance before everyone rejoins.',
    },
    elimination_ladder: {
      title: 'Elimination Ladder',
      badge: 'Pro',
      description: 'Round-by-round elimination by score.',
      helper: 'Everyone answers their own question each round. The lowest score drops out until the final places are decided.',
    },
  };
  const selectedModeLocked = isProGameMode(form.gameMode) && !canUseProModes;
  const selectedPack = packs.find((pack) => pack.id === form.questionPackId);
  const canAdvanceBasics = Boolean(form.name.trim() && form.questionPackId && !selectedModeLocked);
  const isTargetMode = form.gameMode === 'classic' || form.gameMode === 'race_to_points' || form.gameMode === 'speed_round';
  const isEliminationMode = form.gameMode === 'elimination_ladder';
  const canAdvanceRules =
    (form.gameMode === 'classic' ? form.startingPoints > 0 && form.targetPoints > form.startingPoints : isTargetMode || form.startingPoints > 0) &&
    form.targetPoints > 0 &&
    (!isEliminationMode || (form.eliminationRounds > 0 && form.questionsPerRound > 0)) &&
    form.wrongPenalty >= 0 &&
    form.recoveryPoints >= 0 &&
    form.timeLimit >= 5 &&
    form.maxConsecutiveQuestions >= 1;
  const names = memberNames
    .split(/\n|,/)
    .map((name) => name.trim())
    .filter(Boolean);
  const hostNameKey = hostDisplayName.toLowerCase();
  const uniqueNames = [...new Set(names)].filter((name) => !includeHostAsPlayer || name.toLowerCase() !== hostNameKey);
  const reviewPlayers = includeHostAsPlayer ? [hostDisplayName, ...uniqueNames] : uniqueNames;
  const playerCount = uniqueNames.length + (includeHostAsPlayer ? 1 : 0);
  const playerLimitReached = playerCount >= maxPlayersPerGame;
  const playerLimitExceeded = playerCount > maxPlayersPerGame;
  const hostToggleDisabled = !includeHostAsPlayer && playerLimitReached;
  const canAdvancePlayers = playerCount > 0 && !playerLimitExceeded;
  const canFinish = canAdvanceBasics && canAdvanceRules && canAdvancePlayers;

  function syncPlayerNames(nextNames: string[]) {
    setMemberNames(nextNames.join('\n'));
  }

  function addPlayerName(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const nextName = playerNameDraft.trim();
    if (!nextName) return;

    const nextNameKey = nextName.toLowerCase();
    if (
      playerLimitReached ||
      uniqueNames.some((name) => name.toLowerCase() === nextNameKey) ||
      (includeHostAsPlayer && nextNameKey === hostNameKey)
    ) {
      setPlayerNameDraft('');
      return;
    }

    syncPlayerNames([...uniqueNames, nextName]);
    setPlayerNameDraft('');
  }

  function removePlayerName(nameToRemove: string) {
    syncPlayerNames(uniqueNames.filter((name) => name !== nameToRemove));
  }

  function toggleHostPlayer() {
    const nextValue = !includeHostAsPlayer;
    if (nextValue) {
      syncPlayerNames(uniqueNames.filter((name) => name.toLowerCase() !== hostNameKey));
    }
    setIncludeHostAsPlayer(nextValue);
  }

  function canOpenStep(targetStep: number) {
    if (targetStep === 1) return true;
    if (targetStep === 2) return canAdvanceBasics;
    if (targetStep === 3) return canAdvanceBasics && canAdvanceRules;
    return canAdvanceBasics && canAdvanceRules && canAdvancePlayers;
  }

  function goNext() {
    if (step === 1 && !canAdvanceBasics) return;
    if (step === 2 && !canAdvanceRules) return;
    if (step === 3 && !canAdvancePlayers) return;
    setStep((current) => Math.min(4, current + 1));
  }

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Create game wizard">
      <div className="wizard-modal">
        <div className="wizard-header">
          <div>
            <p className="eyebrow">New game</p>
            <h2>Create game</h2>
          </div>
          <button className="icon-button neutral" onClick={onClose} type="button" aria-label="Close wizard" title="Close wizard">
            <X size={18} />
          </button>
        </div>

        <div className="wizard-steps">
          {steps.map((label, index) => (
            <button
              className={`wizard-step ${step === index + 1 ? 'active' : ''} ${step > index + 1 ? 'done' : ''} ${
                !canOpenStep(index + 1) ? 'locked' : ''
              }`}
              key={label}
              disabled={!canOpenStep(index + 1)}
              onClick={() => setStep(index + 1)}
              type="button"
            >
              <span>{index + 1}</span>
              {label}
            </button>
          ))}
        </div>

        <div className="wizard-body">
          {step === 1 && (
            <div className="form-grid">
              <label className="wide">
                Game name
                <input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} placeholder="Friday night knockout" autoFocus />
              </label>
              <section className="wide wizard-pack-picker" aria-label="Choose question pack">
                <div className="wizard-section-heading">
                  <div>
                    <span>Question pack</span>
                    <strong>{selectedPack ? selectedPack.name : 'Choose a pack'}</strong>
                  </div>
                  <em>{packs.length} available</em>
                </div>

                <div className="wizard-pack-list">
                  {packs.length === 0 && <p className="pack-empty-state">No packs are available on this plan yet.</p>}
                  {packs.map((pack) => {
                    const selected = form.questionPackId === pack.id;

                    return (
                      <button
                        className={`wizard-pack-row ${selected ? 'selected' : ''}`}
                        key={pack.id}
                        onClick={() => setForm({ ...form, questionPackId: pack.id })}
                        type="button"
                      >
                        <span className="wizard-pack-check">{selected ? <CheckCircle2 size={16} /> : <BookOpen size={16} />}</span>
                        <div>
                          <strong>{pack.name}</strong>
                          <span>{pack.description || 'Starter quiz pack'}</span>
                        </div>
                        <div className="pack-card-footer">
                          <em>{packQuestionCounts[pack.id] || 0} questions</em>
                          <b>{getPackTierLabel(pack.tier)}</b>
                        </div>
                      </button>
                    );
                  })}
                </div>
              </section>

              <div className="wide mode-choice-wrap">
                <div className="wizard-section-heading">
                  <div>
                    <span>Game mode</span>
                    <strong>{modeDetails[form.gameMode].title}</strong>
                  </div>
                </div>
                <div className="mode-choice-grid">
                  {(Object.keys(modeDetails) as GameMode[]).map((mode) => {
                    const locked = isProGameMode(mode) && !canUseProModes;

                    return (
                      <button
                        className={`mode-choice-card ${form.gameMode === mode ? 'selected' : ''} ${locked ? 'locked' : ''}`}
                        key={mode}
                        onClick={() => {
                          if (locked) {
                            onUpgrade();
                            return;
                          }

                          setForm({
                            ...form,
                            gameMode: mode,
                            startingPoints: mode === 'race_to_points' || mode === 'speed_round' ? 0 : form.startingPoints || 100,
                            targetPoints:
                              mode === 'classic'
                                ? form.targetPoints > (form.startingPoints || 100)
                                  ? form.targetPoints
                                  : (form.startingPoints || 100) + 50
                                : mode === 'race_to_points' || mode === 'speed_round'
                                  ? form.targetPoints || 100
                                  : form.targetPoints,
                            eliminationRounds: mode === 'elimination_ladder' ? form.eliminationRounds || 3 : form.eliminationRounds,
                            questionsPerRound: mode === 'elimination_ladder' ? form.questionsPerRound || 3 : form.questionsPerRound,
                          });
                        }}
                        type="button"
                      >
                        <span className="mode-card-top">
                          <strong>{modeDetails[mode].title}</strong>
                          <em>{modeDetails[mode].badge}</em>
                        </span>
                        <span>{modeDetails[mode].description}</span>
                        {locked && (
                          <span className="mode-lock-note">
                            <Lock size={13} />
                            Upgrade to unlock
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
                <p className="mode-helper">{modeDetails[form.gameMode].helper}</p>
                {selectedModeLocked && <p className="form-helper">Choose a free mode or upgrade to Pro to continue.</p>}
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="form-grid">
              <NumberInput label="Starting points" value={form.startingPoints} onChange={(value) => setForm({ ...form, startingPoints: value })} />
              {isTargetMode && <NumberInput label={form.gameMode === 'classic' ? 'Winning score' : 'Target points'} value={form.targetPoints} onChange={(value) => setForm({ ...form, targetPoints: value })} />}
              {isEliminationMode && <NumberInput label="Ladder rounds" value={form.eliminationRounds} onChange={(value) => setForm({ ...form, eliminationRounds: value })} />}
              {isEliminationMode && <NumberInput label="Questions/round" value={form.questionsPerRound} onChange={(value) => setForm({ ...form, questionsPerRound: value })} />}
              <NumberInput label="Wrong penalty" value={form.wrongPenalty} onChange={(value) => setForm({ ...form, wrongPenalty: value })} />
              <NumberInput label="Correct points" value={form.recoveryPoints} onChange={(value) => setForm({ ...form, recoveryPoints: value })} />
              <NumberInput label="Seconds/question" value={form.timeLimit} onChange={(value) => setForm({ ...form, timeLimit: value })} />
              {form.gameMode !== 'speed_round' && form.gameMode !== 'elimination_ladder' && <NumberInput label="Questions/turn" value={form.maxConsecutiveQuestions} onChange={(value) => setForm({ ...form, maxConsecutiveQuestions: value })} />}
              {!canAdvanceRules && <p className="form-helper wide">Check the scores, winning target, ladder rounds, question count, 5 seconds per question, and at least 1 question per turn.</p>}
            </div>
          )}

          {step === 3 && (
            <div className="player-setup">
              <button
                className={`host-player-card ${includeHostAsPlayer ? 'selected' : ''}`}
                onClick={toggleHostPlayer}
                disabled={hostToggleDisabled}
                type="button"
                aria-pressed={includeHostAsPlayer}
              >
                <span className="host-player-avatar">{getInitials(hostDisplayName) || <User size={18} />}</span>
                <span>
                  <strong>{includeHostAsPlayer ? `${hostDisplayName} is playing` : 'Add host as player'}</strong>
                  <small>{includeHostAsPlayer ? 'The host will join the lobby automatically.' : `${hostDisplayName} can play alongside everyone else.`}</small>
                </span>
                <span className="host-player-state">{includeHostAsPlayer ? <CheckCircle2 size={18} /> : <Plus size={18} />}</span>
              </button>

              <form className="single-player-form" onSubmit={addPlayerName}>
                <label>
                  Add player
                  <input
                    value={playerNameDraft}
                    onChange={(event) => setPlayerNameDraft(event.target.value)}
                    placeholder="Sarah"
                    disabled={playerLimitReached}
                  />
                </label>
                <button className="primary-button" disabled={!playerNameDraft.trim() || playerLimitReached} type="submit">
                  <UserPlus size={18} />
                  Add
                </button>
              </form>

              <div className="wizard-player-list" aria-live="polite">
                <div className="wizard-player-list-header">
                  <span>Players</span>
                  <strong>{playerCount}/{maxPlayersPerGame}</strong>
                </div>
                {reviewPlayers.length === 0 ? (
                  <p className="empty-state">No players added yet.</p>
                ) : (
                  <div className="wizard-player-chips">
                    {includeHostAsPlayer && (
                      <span className="wizard-player-chip host">
                        <strong>{hostDisplayName}</strong>
                        <small>Host</small>
                      </span>
                    )}
                    {uniqueNames.map((name) => (
                      <span className="wizard-player-chip" key={name}>
                        <strong>{name}</strong>
                        <button onClick={() => removePlayerName(name)} type="button" aria-label={`Remove ${name}`} title={`Remove ${name}`}>
                          <X size={14} />
                        </button>
                      </span>
                    ))}
                  </div>
                )}
              </div>
              {playerCount === 0 && <p className="form-helper">Add at least one player, or add the host as a player.</p>}
              {playerLimitReached && !playerLimitExceeded && <p className="field-hint">You have used all player slots for this plan.</p>}
              {playerLimitExceeded && <p className="form-helper">Remove {playerCount - maxPlayersPerGame} player{playerCount - maxPlayersPerGame === 1 ? '' : 's'} to continue on this plan.</p>}
            </div>
          )}

          {step === 4 && (
            <div className="review-grid">
              <div className="review-card wide">
                <span>Name</span>
                <strong>{form.name || 'Untitled game'}</strong>
              </div>
              <div className="review-card">
                <span>Question pack</span>
                <strong>{selectedPack?.name || 'No pack selected'}</strong>
                <small>{selectedPack ? `${packQuestionCounts[selectedPack.id] || 0} questions · ${getPackTierLabel(selectedPack.tier)}` : 'Choose a pack to continue'}</small>
              </div>
              <div className="review-card">
                <span>Mode</span>
                <strong>{getGameModeLabel(form.gameMode)}</strong>
                <small>{modeDetails[form.gameMode].helper}</small>
              </div>
              <div className="review-card">
                <span>Rules</span>
                <strong>
                  {isEliminationMode
                    ? `${form.startingPoints} pts · ${form.eliminationRounds} rounds · ${form.questionsPerRound} questions/round`
                    : isTargetMode
                      ? `${form.startingPoints} start · ${form.targetPoints} ${form.gameMode === 'classic' ? 'to win' : 'target'}`
                      : `${form.startingPoints} pts`} · -{form.wrongPenalty} wrong · +{form.recoveryPoints} correct · {form.timeLimit}s
                </strong>
              </div>
              <div className="review-card">
                <span>Players</span>
                <strong>{playerCount} added</strong>
                <small>{playerCount} of {maxPlayersPerGame} slots used · {includeHostAsPlayer ? `${hostDisplayName} joins automatically` : 'Host is managing only'}</small>
              </div>
              <div className="wide review-card review-player-list">
                <span>Lobby list</span>
                <strong>{reviewPlayers.join(', ')}</strong>
              </div>
            </div>
          )}
        </div>

        {notice && <p className="form-message">{notice}</p>}

        <div className="wizard-actions">
          <button className="ghost-button" disabled={step === 1 || busy} onClick={() => setStep((current) => Math.max(1, current - 1))} type="button">
            Back
          </button>
          {step < 4 ? (
            <button
              className="primary-button"
              disabled={(step === 1 && !canAdvanceBasics) || (step === 2 && !canAdvanceRules) || (step === 3 && !canAdvancePlayers)}
              onClick={goNext}
              type="button"
            >
              Next
            </button>
          ) : (
            <button className="primary-button" disabled={busy || !canFinish} onClick={onSubmit} type="button">
              {busy ? <RefreshCw className="spin" size={18} /> : <CheckCircle2 size={18} />}
              Finish
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function ControlRoomModal({ game, hostMember, onClose }: { game: Game | null; hostMember: GameMember | null; onClose: () => void }) {
  if (!game) return null;

  return (
    <div className="modal-backdrop control-room-backdrop" role="dialog" aria-modal="true" aria-label="Host control room">
      <section className="control-room-modal">
        <button className="control-room-close" onClick={onClose} type="button" aria-label="Close control room" title="Close control room">
          <X size={18} />
        </button>
        <HostGameRoom joinCode={game.join_code} hostMember={hostMember} />
      </section>
    </div>
  );
}

function GameSummaryModal({
  game,
  members,
  answers,
  busy,
  onClose,
}: {
  game: Game | null;
  members: GameMember[];
  answers: GameAnswerSummary[];
  busy: boolean;
  onClose: () => void;
}) {
  if (!game) return null;

  const rankedMembers = [...members].sort((a, b) => b.points - a.points || a.turn_order - b.turn_order);
  const winner = game.status === 'finished' ? rankedMembers[0] || null : null;
  const correctCount = answers.filter((answer) => answer.is_correct).length;
  const biggestRecovery = answers.reduce((best, answer) => (answer.points_delta > (best?.points_delta || 0) ? answer : best), null as GameAnswerSummary | null);

  return (
    <div className="modal-backdrop summary-backdrop" role="dialog" aria-modal="true" aria-label={`${game.name} summary`}>
      <section className="summary-modal">
        <div className="summary-header">
          <div>
            <p className="eyebrow">{game.status === 'finished' ? 'Game summary' : 'Game history'}</p>
            <h2>{game.name}</h2>
            <span className={`status-pill ${game.status}`}>{game.status}</span>
          </div>
          <button className="icon-button neutral" onClick={onClose} type="button" aria-label="Close summary" title="Close summary">
            <X size={18} />
          </button>
        </div>

        {busy ? (
          <div className="summary-loading">
            <RefreshCw className="spin" size={24} />
            <p>Loading summary...</p>
          </div>
        ) : (
          <>
            <div className="summary-hero">
              <div className="summary-winner">
                <span>{winner ? 'Winner' : 'Result'}</span>
                <strong>{winner ? winner.display_name : game.status === 'cancelled' ? 'Game cancelled' : 'No winner recorded'}</strong>
                <p>{winner ? `${winner.points} points` : `${members.length} player${members.length === 1 ? '' : 's'}`}</p>
              </div>
              <div className="summary-stats">
                <div>
                  <span>Players</span>
                  <strong>{members.length}</strong>
                </div>
                <div>
                  <span>Answers</span>
                  <strong>{answers.length}</strong>
                </div>
                <div>
                  <span>Correct</span>
                  <strong>{correctCount}</strong>
                </div>
                <div>
                  <span>Best recovery</span>
                  <strong>{biggestRecovery && biggestRecovery.points_delta > 0 ? `+${biggestRecovery.points_delta}` : '-'}</strong>
                </div>
              </div>
            </div>

            <div className="summary-grid">
              <section className="summary-panel">
                <div className="section-heading compact-heading">
                  <div>
                    <p className="eyebrow">Leaderboard</p>
                    <h2>Final places</h2>
                  </div>
                </div>
                <div className="summary-leaderboard">
                  {rankedMembers.length === 0 ? (
                    <p className="empty-state">No players found for this game.</p>
                  ) : (
                    rankedMembers.map((member, index) => (
                      <article className={`summary-leader-row ${index === 0 && winner ? 'winner' : ''}`} key={member.id}>
                        <span>{getOrdinal(index + 1)}</span>
                        <div>
                          <strong>{member.display_name}</strong>
                          <small>{index === 0 && winner ? 'Winner' : `Turn ${member.turn_order}`}</small>
                        </div>
                        <b>{member.points}</b>
                      </article>
                    ))
                  )}
                </div>
              </section>

              <section className="summary-panel">
                <div className="section-heading compact-heading">
                  <div>
                    <p className="eyebrow">Questions</p>
                    <h2>Answer history</h2>
                  </div>
                </div>
                <div className="answer-history-list">
                  {answers.length === 0 ? (
                    <p className="empty-state">No answers were recorded for this game.</p>
                  ) : (
                    answers.map((answer, index) => (
                      <article className={`answer-history-row ${answer.is_correct ? 'correct' : 'wrong'}`} key={answer.id}>
                        <div className="answer-history-icon">{answer.is_correct ? <CheckCircle2 size={18} /> : <X size={18} />}</div>
                        <div>
                          <strong>
                            {index + 1}. {answer.questions?.prompt || 'Question'}
                          </strong>
                          <span>
                            {answer.game_members?.display_name || 'Player'} chose {answer.selected_option}. Correct: {answer.questions?.correct_option || '-'} ·{' '}
                            {answer.points_delta > 0 ? `+${answer.points_delta}` : answer.points_delta} points
                          </span>
                        </div>
                      </article>
                    ))
                  )}
                </div>
              </section>
            </div>
          </>
        )}
      </section>
    </div>
  );
}

function GameRow({
  game,
  selected,
  busy,
  onCancel,
  onDelete,
  onSelect,
}: {
  game: Game;
  selected: boolean;
  busy: boolean;
  onCancel: () => void;
  onDelete: () => void;
  onSelect: () => void;
}) {
  const joinUrl = getJoinUrl(game.join_code);

  return (
    <article className={`game-row ${selected ? 'selected' : ''}`}>
      <div>
        <h3>{game.name}</h3>
        <p>
          {game.status} · {getGameModeLabel(game.game_mode)} · {game.game_mode === 'elimination_ladder' ? `${game.elimination_rounds} rounds` : game.game_mode === 'race_to_points' || game.game_mode === 'speed_round' ? `Race to ${game.target_points}` : `${game.starting_points} start · ${game.target_points} to win`} · -{game.wrong_answer_penalty} wrong · {game.question_time_limit_seconds}s
        </p>
      </div>
      <div className="join-code">
        <button className="select-button" onClick={onSelect} type="button">
          {selected ? 'Selected' : 'Manage'}
        </button>
        <span>{game.join_code}</span>
        <CopyButton value={joinUrl} label="Copy join link" />
        {game.status === 'active' ? (
          <button className="icon-button danger" disabled={busy} onClick={onCancel} type="button" aria-label="Cancel game" title="Cancel game">
            {busy ? <RefreshCw className="spin" size={18} /> : <X size={18} />}
          </button>
        ) : (
          <button className="icon-button danger" disabled={busy} onClick={onDelete} type="button" aria-label="Delete game" title="Delete game">
            {busy ? <RefreshCw className="spin" size={18} /> : <Trash2 size={18} />}
          </button>
        )}
      </div>
    </article>
  );
}

function MemberGroup({
  title,
  empty,
  members,
  memberDrafts,
  editingMemberId,
  memberActionBusy,
  disabled,
  onCancelEdit,
  onEditMember,
  onMemberDraftChange,
  onRemoveMember,
  onSaveMember,
}: {
  title: string;
  empty: string;
  members: GameMember[];
  memberDrafts: Record<string, MemberDraft>;
  editingMemberId: string;
  memberActionBusy: string;
  disabled: boolean;
  onCancelEdit: () => void;
  onEditMember: (member: GameMember) => void;
  onMemberDraftChange: (memberId: string, patch: Partial<MemberDraft>) => void;
  onRemoveMember: (member: GameMember) => void;
  onSaveMember: (member: GameMember) => void;
}) {
  return (
    <section className="member-group">
      <div className="member-group-header">
        <h3>{title}</h3>
        <span>{members.length}</span>
      </div>
      {members.length === 0 ? (
        <p className="empty-state small-empty">{empty}</p>
      ) : (
        members.map((member) => (
          <MemberEditorRow
            key={member.id}
            member={member}
            draft={memberDrafts[member.id]}
            editing={editingMemberId === member.id}
            busy={memberActionBusy === member.id}
            disabled={disabled}
            onCancel={onCancelEdit}
            onEdit={() => onEditMember(member)}
            onDraftChange={(patch) => onMemberDraftChange(member.id, patch)}
            onRemove={() => void onRemoveMember(member)}
            onSave={() => void onSaveMember(member)}
          />
        ))
      )}
    </section>
  );
}

function MemberEditorRow({
  member,
  draft,
  editing,
  busy,
  disabled,
  onCancel,
  onDraftChange,
  onEdit,
  onRemove,
  onSave,
}: {
  member: GameMember;
  draft?: MemberDraft;
  editing: boolean;
  busy: boolean;
  disabled: boolean;
  onCancel: () => void;
  onDraftChange: (patch: Partial<MemberDraft>) => void;
  onEdit: () => void;
  onRemove: () => void;
  onSave: () => void;
}) {
  const statusLabel = member.status === 'invited' ? 'Waiting' : member.status === 'joined' ? 'Joined' : member.status === 'active' ? 'Playing' : member.status;
  const statusClass = member.status === 'active' ? 'joined' : member.status;

  if (editing) {
    return (
      <article className="member-row editing">
        <label>
          Order
          <input
            value={draft?.turn_order ?? member.turn_order}
            onChange={(event) => onDraftChange({ turn_order: Number(event.target.value) })}
            type="number"
            min={1}
          />
        </label>
        <div className="member-edit-grid">
          <label>
            Name
            <input
              value={draft?.display_name ?? member.display_name}
              onChange={(event) => onDraftChange({ display_name: event.target.value })}
            />
          </label>
          <label>
            Points
            <input
              value={draft?.points ?? member.points}
              onChange={(event) => onDraftChange({ points: Number(event.target.value) })}
              type="number"
              min={0}
            />
          </label>
        </div>
        <div className="member-actions">
          <button className="icon-button" disabled={busy} onClick={onSave} type="button" aria-label="Save player" title="Save player">
            {busy ? <RefreshCw className="spin" size={18} /> : <Save size={18} />}
          </button>
          <button className="icon-button neutral" disabled={busy} onClick={onCancel} type="button" aria-label="Cancel edit" title="Cancel edit">
            <X size={18} />
          </button>
        </div>
      </article>
    );
  }

  return (
    <article className="member-row">
      <div className="turn-order">{member.turn_order}</div>
      <div>
        <h3>{member.display_name}</h3>
        <div className="member-meta">
          <span className={`member-status ${statusClass}`}>{statusLabel}</span>
          <span>{member.points} pts</span>
        </div>
      </div>
      <div className="member-actions">
        <button className="icon-button" disabled={disabled || busy} onClick={onEdit} type="button" aria-label="Edit player" title="Edit player">
          <Pencil size={18} />
        </button>
        <button className="icon-button danger" disabled={disabled || busy} onClick={onRemove} type="button" aria-label="Remove player" title="Remove player">
          {busy ? <RefreshCw className="spin" size={18} /> : <Trash2 size={18} />}
        </button>
      </div>
    </article>
  );
}

type JoinGamePayload = {
  game: {
    id: string;
    name: string;
    join_code: string;
    status: string;
    game_mode?: string;
    target_points?: number;
    elimination_rounds?: number;
    questions_per_round?: number;
    starting_points: number;
    question_time_limit_seconds: number;
  };
  members: Array<{
    id: string;
    display_name: string;
    points: number;
    status: string;
    turn_order: number;
    joined_at: string | null;
  }>;
};

type GuestSession = {
  memberId: string;
  token: string;
};

type GameRoomPayload = {
  game: {
    id: string;
    name: string;
    join_code: string;
    status: string;
    game_mode?: string;
    target_points?: number;
    elimination_rounds?: number;
    questions_per_round?: number;
    question_time_limit_seconds?: number;
    timer_ends_at: string | null;
    current_member_id: string | null;
    current_question_id: string | null;
    current_turn_attempt?: number;
    max_consecutive_questions?: number;
  };
  active_member: {
    id: string;
    display_name: string;
    points: number;
  } | null;
  question: {
    id: string;
    prompt: string;
    option_a: string;
    option_b: string;
    option_c: string;
  } | null;
  members: Array<{
    id: string;
    display_name: string;
    points: number;
    status: string;
    turn_order: number;
  }>;
  events: Array<{
    id: string;
    member_id?: string | null;
    event_type: string;
    message: string;
    metadata?: {
      ladder_round?: number;
      points?: number;
      [key: string]: unknown;
    } | null;
    created_at: string;
  }>;
  latest_answer: AnswerResult | null;
  submitted_answer?: AnswerResult | null;
  speed_round: {
    id: string;
    round_number: number;
    timer_ends_at: string;
    answered_member_ids: string[];
    answers: Array<{
      id: string;
      member_id: string;
      member_name: string;
      selected_option: string;
      is_correct: boolean | null;
      points_delta: number;
      attempt?: number;
      answered_at: string;
    }>;
  } | null;
};

type AnswerResult = {
    id: string;
    member_id?: string;
    member_name: string;
    selected_option: string;
    is_correct: boolean;
    points_delta: number;
    attempt?: number;
    correct_option: string;
    correct_answer: string;
    answered_at: string;
};

function getGameModeLabel(mode?: string | null) {
  if (mode === 'elimination_ladder') return 'Elimination Ladder';
  if (mode === 'speed_round') return 'Speed Round';
  if (mode === 'race_to_points') return 'Race to Points';
  return 'Classic';
}

function JoinGame({ joinCode }: { joinCode: string }) {
  const [payload, setPayload] = useState<JoinGamePayload | null>(null);
  const [room, setRoom] = useState<GameRoomPayload | null>(null);
  const [selectedMemberId, setSelectedMemberId] = useState('');
  const [claimedName, setClaimedName] = useState('');
  const [guestSession, setGuestSession] = useState<GuestSession | null>(() => readGuestSession(joinCode));
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const refreshInFlightRef = useRef(false);

  useEffect(() => {
    void loadJoinGame();
  }, [joinCode]);

  useEffect(() => {
    const gameId = room?.game.id || payload?.game.id;
    if (!gameId) return undefined;

    const channel = supabase
      .channel(`guest-game-${gameId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'game_members', filter: `game_id=eq.${gameId}` },
        () => void loadJoinGame(false),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'games', filter: `id=eq.${gameId}` },
        () => void loadJoinGame(false),
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'game_events', filter: `game_id=eq.${gameId}` },
        () => void loadJoinGame(false),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'speed_rounds', filter: `game_id=eq.${gameId}` },
        () => void loadJoinGame(false),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'speed_round_answers', filter: `game_id=eq.${gameId}` },
        () => void loadJoinGame(false),
      )
      .subscribe();

    const pollId = window.setInterval(() => void loadJoinGame(false), room ? 5000 : 3000);

    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') {
        void loadJoinGame(false);
      }
    };

    document.addEventListener('visibilitychange', refreshWhenVisible);
    window.addEventListener('focus', refreshWhenVisible);

    return () => {
      window.clearInterval(pollId);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
      window.removeEventListener('focus', refreshWhenVisible);
      void supabase.removeChannel(channel);
    };
  }, [payload?.game.id, room?.game.id]);

  async function loadJoinGame(showLoading = true) {
    if (refreshInFlightRef.current) return;
    refreshInFlightRef.current = true;
    if (showLoading) {
      setLoading(true);
      setMessage('');
    }

    try {
      const { data, error } = await supabase.rpc('get_joinable_game', { p_join_code: joinCode });

      if (showLoading) setLoading(false);

      if (error) {
        setMessage(error.message);
        return;
      }

      const nextPayload = data as JoinGamePayload;
      setPayload(nextPayload);
      setSelectedMemberId((current) => current || nextPayload.members.find((member) => member.status === 'invited')?.id || '');

      if (nextPayload.game.status === 'active' || nextPayload.game.status === 'finished') {
        const roomResult = await supabase.rpc('get_game_room', { p_join_code: joinCode });
        if (!roomResult.error) {
          setRoom(roomResult.data as GameRoomPayload);
        }
      } else {
        setRoom(null);
      }
    } finally {
      if (showLoading) setLoading(false);
      refreshInFlightRef.current = false;
    }
  }

  async function claimMember(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedMemberId) {
      setMessage('Choose your name to join.');
      return;
    }

    setBusy(true);
    setMessage('');

    const { data, error } = await supabase.rpc('claim_game_member', {
      p_join_code: joinCode,
      p_member_id: selectedMemberId,
    });

    setBusy(false);

    if (error) {
      setMessage(error.message);
      await loadJoinGame();
      return;
    }

    const claim = data as { session_token: string; member: { id: string; display_name: string } };
    const nextSession = { memberId: claim.member.id, token: claim.session_token };
    localStorage.setItem(`quiz_guest_${joinCode}`, JSON.stringify(nextSession));
    setGuestSession(nextSession);
    setClaimedName(claim.member.display_name);
    setMessage('You are in the lobby.');
    await loadJoinGame();
  }

  const invitedMembers = payload?.members.filter((member) => member.status === 'invited') || [];
  const joinedMembers = payload?.members.filter((member) => member.status === 'joined') || [];
  const headerGameName = room?.game.name || payload?.game.name || 'Game';

  return (
    <main className="join-layout game-stage">
      <div className="member-corner-logo">
        <div className="brand-mark small">
          <LogoMark size={26} />
        </div>
        <span>Quizo</span>
        <i aria-hidden="true" />
        <strong className="member-game-name">{headerGameName}</strong>
        <b>{room?.game.status === 'finished' ? 'Game finished' : room ? 'Live game' : 'Lobby'}</b>
      </div>
      <section className={`join-panel ${room ? 'live-game-panel' : ''}`}>
        {loading ? (
          <div className="join-state">
            <div className="brand-mark small">
              <LogoMark size={26} />
            </div>
            <div>
              <span>Loading game</span>
              <p>Finding your lobby and latest scores.</p>
            </div>
            <LoadingDots />
          </div>
        ) : room ? (
          <GameRoom
            room={room}
            joinCode={joinCode}
            playerIdentity={guestSession ? { memberId: guestSession.memberId, token: guestSession.token, kind: 'guest' } : null}
            onRefresh={() => loadJoinGame(false)}
          />
        ) : payload ? (
          <>
            <div className="join-heading">
              <p className="eyebrow">Game code {payload.game.join_code}</p>
              <h1>{payload.game.name}</h1>
              <p>
                {payload.game.status} · {getGameModeLabel(payload.game.game_mode)} · {payload.game.game_mode === 'elimination_ladder' ? `${payload.game.elimination_rounds || 3} rounds · ${payload.game.questions_per_round || 3} questions/round` : payload.game.game_mode === 'race_to_points' || payload.game.game_mode === 'speed_round' ? `Race to ${payload.game.target_points || 100}` : `${payload.game.starting_points} start · ${payload.game.target_points || 150} to win`} · {payload.game.question_time_limit_seconds}s per question
              </p>
            </div>

            {claimedName ? (
              <div className="claimed-box">
                <CheckCircle2 size={26} />
                <div>
                  <strong>{claimedName}</strong>
                  <span>Waiting for the host to start.</span>
                </div>
              </div>
            ) : (
              <form className="stack" onSubmit={claimMember}>
                <label>
                  Choose your name
                  <select value={selectedMemberId} onChange={(event) => setSelectedMemberId(event.target.value)} required>
                    <option value="">Select invited name</option>
                    {invitedMembers.map((member) => (
                      <option key={member.id} value={member.id}>
                        {member.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <button className="primary-button" disabled={busy || invitedMembers.length === 0} type="submit">
                  {busy ? <RefreshCw className="spin" size={18} /> : <CheckCircle2 size={18} />}
                  Join lobby
                </button>
              </form>
            )}

            {message && <p className="form-message">{message}</p>}

            <div className="lobby-columns">
              <div>
                <h2>Lobby</h2>
                <div className="member-list compact">
                  {invitedMembers.length === 0 ? (
                    <p className="empty-state">Everyone has joined.</p>
                  ) : (
                    invitedMembers.map((member) => <LobbyMember key={member.id} member={member} />)
                  )}
                </div>
              </div>
              <div>
                <h2>Who's joined</h2>
                <div className="member-list compact">
                  {joinedMembers.length === 0 ? (
                    <p className="empty-state">No one has joined yet.</p>
                  ) : (
                    joinedMembers.map((member) => <LobbyMember key={member.id} member={member} />)
                  )}
                </div>
              </div>
            </div>
          </>
        ) : (
          <div className="join-state">
            <p>{message || 'Game not found.'}</p>
          </div>
        )}
      </section>
    </main>
  );
}

function readGuestSession(joinCode: string): GuestSession | null {
  try {
    const raw = localStorage.getItem(`quiz_guest_${joinCode}`);
    return raw ? (JSON.parse(raw) as GuestSession) : null;
  } catch {
    return null;
  }
}

function LobbyMember({ member }: { member: JoinGamePayload['members'][number] }) {
  return (
    <article className="member-row">
      <div className="turn-order member-avatar">{getInitials(member.display_name)}</div>
      <div>
        <h3>{member.display_name}</h3>
        <p>
          {member.status} · {member.points} pts
        </p>
      </div>
    </article>
  );
}

function myMemberIsActive(members: GameRoomPayload['members'], memberId: string) {
  return members.some((member) => member.id === memberId && member.status === 'active');
}

function HostGameRoom({ joinCode, hostMember }: { joinCode: string; hostMember: GameMember | null }) {
  const [room, setRoom] = useState<GameRoomPayload | null>(null);
  const [message, setMessage] = useState('');

  useEffect(() => {
    void loadRoom();
  }, [joinCode]);

  useEffect(() => {
    if (!room?.game.id) return undefined;

    const channel = supabase
      .channel(`host-game-room-${room.game.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'games', filter: `id=eq.${room.game.id}` }, () => void loadRoom())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'game_members', filter: `game_id=eq.${room.game.id}` }, () => void loadRoom())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'game_events', filter: `game_id=eq.${room.game.id}` }, () => void loadRoom())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'speed_rounds', filter: `game_id=eq.${room.game.id}` }, () => void loadRoom())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'speed_round_answers', filter: `game_id=eq.${room.game.id}` }, () => void loadRoom())
      .subscribe();

    const pollId = window.setInterval(() => void loadRoom(), 5000);

    return () => {
      window.clearInterval(pollId);
      void supabase.removeChannel(channel);
    };
  }, [room?.game.id]);

  async function loadRoom() {
    const { data, error } = await supabase.rpc('get_game_room', { p_join_code: joinCode });

    if (error) {
      setMessage(error.message);
      return;
    }

    setRoom(data as GameRoomPayload);
  }

  return (
    <section className="host-live-section game-stage">
      {message && <p className="form-message">{message}</p>}
      {room ? (
        <GameRoom
          room={room}
          joinCode={joinCode}
          playerIdentity={hostMember ? { memberId: hostMember.id, kind: 'authenticated' } : null}
          onRefresh={loadRoom}
        />
      ) : (
        <p className="empty-state">Loading live game...</p>
      )}
    </section>
  );
}

function GameRoom({
  room,
  joinCode,
  playerIdentity,
  onRefresh,
}: {
  room: GameRoomPayload;
  joinCode: string;
  playerIdentity: { memberId: string; token?: string; kind: 'guest' | 'authenticated' } | null;
  onRefresh: () => Promise<void>;
}) {
  const [answerBusy, setAnswerBusy] = useState(false);
  const [answerMessage, setAnswerMessage] = useState('');
  const [privateAnswer, setPrivateAnswer] = useState<AnswerResult | null>(null);
  const [visibleAnswerId, setVisibleAnswerId] = useState<string | null>(null);
  const [visibleTimeoutId, setVisibleTimeoutId] = useState<string | null>(null);
  const [now, setNow] = useState(Date.now());
  const [displayTurnTimer, setDisplayTurnTimer] = useState<{ key: string; activeAtMs: number; endsAtMs: number } | null>(null);
  const [soundEnabled, setSoundEnabled] = useState(() => {
    if (typeof window === 'undefined') return true;
    return localStorage.getItem(SOUND_PREFERENCE_KEY) !== 'false';
  });
  const audioContextRef = useRef<AudioContext | null>(null);
  const expiringTurnRef = useRef<string | null>(null);
  const latestAnswerRef = useRef<string | null>(room.latest_answer?.id || null);
  const latestTimeoutRef = useRef<string | null>(null);
  const latestTickRef = useRef('');
  const finalSoundRef = useRef('');

  const isSpeedRound = room.game.game_mode === 'speed_round';
  const isEliminationLadder = room.game.game_mode === 'elimination_ladder';
  const isSharedQuestionMode = isSpeedRound || isEliminationLadder;
  const mySpeedAnswers = playerIdentity?.memberId ? room.speed_round?.answers.filter((answer) => answer.member_id === playerIdentity.memberId) || [] : [];
  const myLatestSpeedAnswer = mySpeedAnswers[mySpeedAnswers.length - 1] || null;
  const hasAnsweredSharedQuestion = Boolean(isEliminationLadder && mySpeedAnswers.length > 0);
  const inferredSpeedLockMemberId =
    isSpeedRound &&
    room.game.current_turn_attempt === 2 &&
    room.latest_answer &&
    !room.latest_answer.is_correct &&
    room.latest_answer.selected_option !== 'TIMEOUT'
      ? room.latest_answer.member_id || room.members.find((member) => member.display_name === room.latest_answer?.member_name)?.id || null
      : null;
  const speedLockedMemberId = isSpeedRound ? room.game.current_member_id || inferredSpeedLockMemberId : null;
  const speedLockedMember = speedLockedMemberId ? room.members.find((member) => member.id === speedLockedMemberId) || null : null;
  const speedIsSecondChance = isSpeedRound && Boolean(speedLockedMember);
  const hasSpeedSecondChance = Boolean(speedIsSecondChance && playerIdentity?.memberId === speedLockedMemberId);
  const isMyTurn = isSharedQuestionMode
    ? Boolean(
        playerIdentity?.memberId &&
          myMemberIsActive(room.members, playerIdentity.memberId) &&
          (!isSpeedRound || !speedLockedMemberId || speedLockedMemberId === playerIdentity.memberId) &&
          (!isEliminationLadder || !hasAnsweredSharedQuestion),
      )
    : Boolean(playerIdentity?.memberId && playerIdentity.memberId === room.game.current_member_id);
  const myMember = playerIdentity ? room.members.find((member) => member.id === playerIdentity.memberId) || null : null;
  const latestTimeoutEvent = room.events.find((event) => event.event_type === 'turn_timed_out') || null;
  const latestLadderResultEvent = isEliminationLadder ? room.events.find((event) => ['player_eliminated', 'ladder_round_tied', 'ladder_final_tied'].includes(event.event_type)) || null : null;
  const isLadderTieResult = latestLadderResultEvent?.event_type === 'ladder_round_tied' || latestLadderResultEvent?.event_type === 'ladder_final_tied';
  const roundResultAgeMs = latestLadderResultEvent ? now - new Date(latestLadderResultEvent.created_at).getTime() : Number.POSITIVE_INFINITY;
  const roundResultVisible = Boolean(latestLadderResultEvent && roundResultAgeMs >= 0 && roundResultAgeMs <= LADDER_ROUND_RESULT_DURATION_MS);
  const roundResultSeconds = roundResultVisible ? Math.max(1, Math.ceil((LADDER_ROUND_RESULT_DURATION_MS - roundResultAgeMs) / 1000)) : 0;
  const roundLoser = !isLadderTieResult && latestLadderResultEvent?.member_id ? room.members.find((member) => member.id === latestLadderResultEvent.member_id) || null : null;
  const roundWinner = isEliminationLadder ? [...room.members].sort((a, b) => b.points - a.points || a.turn_order - b.turn_order)[0] || null : null;
  const ladderRoundNumber = Math.max(1, Math.ceil((room.speed_round?.round_number || 1) / (room.game.questions_per_round || 3)));
  const timerEndMs = room.game.timer_ends_at ? new Date(room.game.timer_ends_at).getTime() : null;
  const timeLimit = room.game.question_time_limit_seconds || 10;
  const timeLimitMs = timeLimit * 1000;
  const turnTimerKey = `${room.game.status}:${room.game.current_question_id || 'none'}:${room.game.timer_ends_at || 'none'}`;
  const displayTimerReady = displayTurnTimer?.key === turnTimerKey;
  const remainingMs = displayTimerReady ? Math.max(0, displayTurnTimer.endsAtMs - now) : timerEndMs ? Math.max(0, timerEndMs - now) : 0;
  const revealHoldMs = displayTimerReady ? Math.max(0, displayTurnTimer.activeAtMs - now) : Math.max(0, remainingMs - timeLimitMs);
  const preparingNextQuestion = room.game.status === 'active' && !roundResultVisible && Boolean(timerEndMs) && (revealHoldMs > 0 || remainingMs > timeLimitMs);
  const nextQuestionInSeconds = preparingNextQuestion ? Math.ceil((revealHoldMs > 0 ? revealHoldMs : remainingMs - timeLimitMs) / 1000) : 0;
  const visibleRemainingMs = revealHoldMs > 0 ? timeLimitMs : Math.min(remainingMs, timeLimitMs);
  const secondsLeft = Math.ceil(visibleRemainingMs / 1000);
  const timerProgress = timerEndMs ? Math.min(100, Math.max(0, ((timeLimitMs - visibleRemainingMs) / timeLimitMs) * 100)) : 0;
  const timerRatio = timeLimit > 0 ? Math.max(0, Math.min(1, visibleRemainingMs / timeLimitMs)) : 0;
  const timerHue = Math.round(6 + timerRatio * 28);
  const timerLightness = Math.round(84 + timerRatio * 8);
  const timerColor = `hsl(${timerHue} 82% ${timerLightness}%)`;
  const winner = room.game.status === 'finished' ? room.members.find((member) => member.status === 'active') || room.members[0] : null;
  const currentAttempt = room.game.current_turn_attempt || 1;
  const maxAttempts = room.game.max_consecutive_questions || 2;
  const isRecoveryQuestion = !isSpeedRound && currentAttempt > 1;
  const toastAnswer = isEliminationLadder ? privateAnswer : room.latest_answer;
  const latestAnswerIsTimeout = toastAnswer?.selected_option === 'TIMEOUT';
  const resultToastVisible = Boolean(toastAnswer && !latestAnswerIsTimeout && visibleAnswerId === toastAnswer.id);
  const timeoutToastVisible = Boolean(latestTimeoutEvent && visibleTimeoutId === latestTimeoutEvent.id);
  const delayingFinalReveal = room.game.status === 'finished' && (resultToastVisible || timeoutToastVisible || roundResultVisible);
  const showFinalResults = room.game.status === 'finished' && !delayingFinalReveal;

  function getAudioContext() {
    const AudioContextClass = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextClass) return null;

    if (!audioContextRef.current) {
      audioContextRef.current = new AudioContextClass();
    }

    return audioContextRef.current;
  }

  function playTone(frequency: number, startTime: number, duration: number, type: OscillatorType, gain = 0.08) {
    const context = getAudioContext();
    if (!context || !soundEnabled) return;

    const oscillator = context.createOscillator();
    const envelope = context.createGain();

    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, startTime);
    envelope.gain.setValueAtTime(0.0001, startTime);
    envelope.gain.exponentialRampToValueAtTime(gain, startTime + 0.015);
    envelope.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);
    oscillator.connect(envelope);
    envelope.connect(context.destination);
    oscillator.start(startTime);
    oscillator.stop(startTime + duration + 0.02);
  }

  function playGameSound(kind: 'correct' | 'wrong' | 'recovered' | 'timeout' | 'tick' | 'winner') {
    if (!soundEnabled) return;

    const context = getAudioContext();
    if (!context) return;

    if (context.state === 'suspended') {
      void context.resume();
    }

    const start = context.currentTime;

    if (kind === 'correct') {
      playTone(660, start, 0.1, 'sine', 0.07);
      playTone(880, start + 0.09, 0.14, 'sine', 0.07);
      return;
    }

    if (kind === 'recovered') {
      playTone(520, start, 0.09, 'sine', 0.07);
      playTone(740, start + 0.08, 0.1, 'sine', 0.07);
      playTone(1040, start + 0.17, 0.16, 'sine', 0.08);
      return;
    }

    if (kind === 'wrong') {
      playTone(210, start, 0.16, 'sawtooth', 0.055);
      playTone(150, start + 0.12, 0.18, 'sawtooth', 0.045);
      return;
    }

    if (kind === 'timeout') {
      playTone(180, start, 0.12, 'square', 0.05);
      playTone(140, start + 0.16, 0.18, 'square', 0.045);
      return;
    }

    if (kind === 'tick') {
      playTone(920, start, 0.055, 'triangle', 0.045);
      return;
    }

    playTone(520, start, 0.1, 'sine', 0.065);
    playTone(660, start + 0.09, 0.1, 'sine', 0.065);
    playTone(880, start + 0.18, 0.16, 'sine', 0.075);
  }

  function toggleSound() {
    const nextValue = !soundEnabled;
    setSoundEnabled(nextValue);
    localStorage.setItem(SOUND_PREFERENCE_KEY, String(nextValue));
  }

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 100);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (room.game.status !== 'active' || !room.game.current_question_id || !timerEndMs) {
      setDisplayTurnTimer(null);
      return;
    }

    const receivedAtMs = Date.now();
    const serverRemainingMs = Math.max(0, timerEndMs - receivedAtMs);
    const resultHoldMs = roundResultVisible ? LADDER_ROUND_RESULT_DURATION_MS : resultToastVisible || timeoutToastVisible ? RESULT_TOAST_DURATION_MS : 0;
    const activeAtMs = resultHoldMs ? receivedAtMs + resultHoldMs : receivedAtMs;
    const endsAtMs = serverRemainingMs > timeLimitMs ? receivedAtMs + serverRemainingMs : activeAtMs + timeLimitMs;

    setDisplayTurnTimer({ key: turnTimerKey, activeAtMs, endsAtMs });
  }, [turnTimerKey, resultToastVisible, roundResultVisible, timeoutToastVisible, timeLimitMs, timerEndMs, room.game.status, room.game.current_question_id]);

  useEffect(() => {
    if (!toastAnswer?.id || toastAnswer.selected_option === 'TIMEOUT') {
      setVisibleAnswerId(null);
      return undefined;
    }

    const isNewAnswer = latestAnswerRef.current !== toastAnswer.id;
    latestAnswerRef.current = toastAnswer.id;
    const answerAgeMs = Date.now() - new Date(toastAnswer.answered_at).getTime();
    const isFreshByTime = answerAgeMs >= 0 && answerAgeMs <= RESULT_TOAST_DURATION_MS;

    if (!isNewAnswer && !isFreshByTime) {
      setVisibleAnswerId(null);
      return undefined;
    }

    setVisibleAnswerId(toastAnswer.id);
    if (isNewAnswer) {
      playGameSound(toastAnswer.is_correct ? ((toastAnswer.attempt || 1) > 1 ? 'recovered' : 'correct') : 'wrong');
    }
    const revealTimer = window.setTimeout(() => setVisibleAnswerId(null), RESULT_TOAST_DURATION_MS);
    return () => window.clearTimeout(revealTimer);
  }, [toastAnswer?.id]);

  useEffect(() => {
    if (!latestTimeoutEvent?.id) {
      setVisibleTimeoutId(null);
      return undefined;
    }

    const isNewTimeout = latestTimeoutRef.current !== latestTimeoutEvent.id;
    latestTimeoutRef.current = latestTimeoutEvent.id;
    const eventAgeMs = Date.now() - new Date(latestTimeoutEvent.created_at).getTime();
    const isFreshByTime = eventAgeMs >= 0 && eventAgeMs <= RESULT_TOAST_DURATION_MS;

    if (!isNewTimeout && !isFreshByTime) {
      setVisibleTimeoutId(null);
      return undefined;
    }

    setVisibleTimeoutId(latestTimeoutEvent.id);
    if (isNewTimeout) {
      playGameSound('timeout');
    }
    const revealTimer = window.setTimeout(() => setVisibleTimeoutId(null), RESULT_TOAST_DURATION_MS);
    return () => window.clearTimeout(revealTimer);
  }, [latestTimeoutEvent?.id]);

  useEffect(() => {
    if (room.game.status !== 'active' || preparingNextQuestion || roundResultVisible || delayingFinalReveal || secondsLeft > 3 || secondsLeft <= 0) return;

    const tickKey = `${turnTimerKey}:${secondsLeft}`;
    if (latestTickRef.current === tickKey) return;

    latestTickRef.current = tickKey;
    playGameSound('tick');
  }, [delayingFinalReveal, preparingNextQuestion, roundResultVisible, room.game.status, secondsLeft, turnTimerKey]);

  useEffect(() => {
    if (!showFinalResults) return;

    const finalKey = `${room.game.id}:${room.game.status}`;
    if (finalSoundRef.current === finalKey) return;

    finalSoundRef.current = finalKey;
    playGameSound('winner');
  }, [room.game.id, room.game.status, showFinalResults]);

  useEffect(() => {
    if (room.game.status !== 'active' || roundResultVisible || !room.game.current_question_id || secondsLeft > 0) return;
    if (expiringTurnRef.current === room.game.current_question_id) return;

    expiringTurnRef.current = room.game.current_question_id;
    void expireTurn();
  }, [room.game.status, room.game.current_question_id, roundResultVisible, secondsLeft]);

  async function expireTurn() {
    const { error } = await supabase.rpc('expire_current_turn', {
      p_join_code: joinCode,
    });

    if (error && !error.message.includes('Turn timer has not expired')) {
      setAnswerMessage(error.message);
    }

    await onRefresh();
  }

  async function submitAnswer(option: string) {
    if (!playerIdentity) {
      setAnswerMessage('This browser has not claimed the active player.');
      return;
    }

    setAnswerBusy(true);
    setAnswerMessage('');

    const answerRpc = isEliminationLadder ? 'submit_elimination_ladder_answer' : isSpeedRound ? 'submit_speed_round_answer' : 'submit_game_answer';
    const { data, error } = await supabase.rpc(answerRpc, {
      p_join_code: joinCode,
      p_member_id: playerIdentity.memberId,
      p_session_token: playerIdentity.token || '',
      p_selected_option: option,
    });

    setAnswerBusy(false);

    if (error) {
      setAnswerMessage(error.message);
      await onRefresh();
      return;
    }

    if (isEliminationLadder) {
      const privateResult = (data as GameRoomPayload | null)?.submitted_answer || null;
      if (privateResult) {
        setPrivateAnswer(privateResult);
      }
    }

    await onRefresh();
  }

  return (
    <div className="game-room">
      {toastAnswer && resultToastVisible && <AnswerResultToast key={toastAnswer.id} answer={toastAnswer} />}
      {latestTimeoutEvent && timeoutToastVisible && <TimeoutResultToast key={latestTimeoutEvent.id} event={latestTimeoutEvent} />}
      <div className="game-room-header">
        <div className="game-room-header-spacer" aria-hidden="true" />
        <div className="game-room-status">
          <p className="eyebrow">{showFinalResults ? 'Game finished' : delayingFinalReveal ? 'Final answer' : 'Live game'}</p>
        </div>
      </div>

      {showFinalResults ? (
        <div className="final-results">
          <div className="winner-panel">
            <ConfettiBurst />
            <div className="winner-avatar">{winner ? getInitials(winner.display_name) : <PartyPopper size={34} />}</div>
            <div>
              <span>Last player standing</span>
              <strong>{winner ? `${winner.display_name} wins` : 'Game finished'}</strong>
              <span>Final scores</span>
            </div>
          </div>
          <FinalLeaderboard members={room.members} winnerId={winner?.id || null} />
        </div>
      ) : (
        <div className={`live-play-layout ${delayingFinalReveal ? 'final-reveal-wait' : ''}`}>
          <div
            className={`turn-banner ${isMyTurn ? 'is-my-turn' : ''} ${delayingFinalReveal ? 'final-reveal' : ''}`}
            style={
              {
                '--timer-progress': `${delayingFinalReveal ? 100 : timerProgress}%`,
                '--timer-color': timerColor,
              } as React.CSSProperties
            }
          >
            <div>
              <span>
                {delayingFinalReveal
                  ? 'Final answer'
                  : roundResultVisible
                    ? `Round ${latestLadderResultEvent?.metadata?.ladder_round || ladderRoundNumber} complete`
                  : preparingNextQuestion
                    ? isSpeedRound
                      ? 'Next round'
                      : isRecoveryQuestion
                        ? 'Second chance next'
                        : 'Up next'
                    : isEliminationLadder
                      ? 'Everyone answers'
                      : isSpeedRound
                      ? 'Everyone answers'
                      : isRecoveryQuestion
                        ? 'Recovery question'
                        : 'On turn'}
              </span>
              <strong>{delayingFinalReveal ? toastAnswer?.member_name || room.active_member?.display_name || 'Last answer' : roundResultVisible ? isLadderTieResult ? 'Scores tied' : `${roundLoser?.display_name || 'Lowest score'} is out` : isEliminationLadder ? `${room.speed_round?.answers.length || 0} answered` : isSpeedRound ? speedLockedMember ? `${speedLockedMember.display_name}'s second chance` : 'Open to everyone' : room.active_member?.display_name || 'Waiting'}</strong>
              <small>
                {delayingFinalReveal
                  ? 'Revealing the winner next'
                  : roundResultVisible
                    ? roundWinner
                      ? isLadderTieResult
                        ? 'No one is eliminated. Tie-break question coming up.'
                        : `${roundWinner.display_name} leads this round. Next question starts shortly.`
                      : 'Next round starts shortly.'
                  : preparingNextQuestion
                  ? isEliminationLadder
                    ? 'Get ready for the next ladder question'
                    : isSpeedRound
                    ? speedLockedMember
                      ? `${speedLockedMember.display_name} gets one more go`
                      : 'Get ready for the next shared question'
                    : isRecoveryQuestion
                      ? 'Get it right to recover the points'
                      : 'Get ready'
                    : isEliminationLadder
                      ? hasAnsweredSharedQuestion
                        ? 'Answer locked. Waiting for everyone else.'
                        : `You are ${myMember ? myMember.display_name : 'watching'}`
                      : isSpeedRound
                      ? hasSpeedSecondChance
                          ? 'Second chance: pick again to recover'
                          : speedLockedMember
                            ? `Waiting for ${speedLockedMember.display_name}`
                            : `You are ${myMember ? myMember.display_name : 'watching'}`
                    : isRecoveryQuestion
                      ? 'Get it right to win the points back'
                      : `You are ${myMember ? myMember.display_name : 'watching'}`}
              </small>
            </div>
            <div className="turn-meta">
              <span>{delayingFinalReveal ? 'Result' : roundResultVisible ? 'Next round' : preparingNextQuestion ? 'Starts in' : isEliminationLadder ? `Round ${ladderRoundNumber}` : isSpeedRound ? 'Round' : isRecoveryQuestion ? 'Chance' : 'Question'}</span>
              <strong>
                {delayingFinalReveal ? 'Soon' : roundResultVisible ? `${roundResultSeconds}s` : preparingNextQuestion ? `${nextQuestionInSeconds}s` : isEliminationLadder ? `${currentAttempt} / ${room.game.questions_per_round || 3}` : isSpeedRound ? `${room.speed_round?.round_number || currentAttempt}` : isRecoveryQuestion ? `${currentAttempt} / ${maxAttempts}` : `${currentAttempt} / ${maxAttempts}`}
              </strong>
              {!preparingNextQuestion && !roundResultVisible && !delayingFinalReveal && (
                <div className="turn-countdown">
                  <span>{secondsLeft}s</span>
                </div>
              )}
            </div>
          </div>
          <section className="question-panel">
            <button className={`sound-toggle question-sound-toggle ${soundEnabled ? 'enabled' : ''}`} onClick={toggleSound} type="button" aria-label={soundEnabled ? 'Turn sound off' : 'Turn sound on'} title={soundEnabled ? 'Sound on' : 'Sound off'}>
              {soundEnabled ? <Volume2 size={16} /> : <VolumeX size={16} />}
            </button>
            {roundResultVisible ? (
              <LadderRoundResult
                roundNumber={latestLadderResultEvent?.metadata?.ladder_round || ladderRoundNumber}
                winner={roundWinner}
                loser={roundLoser}
                seconds={roundResultSeconds}
                isFinal={room.game.status === 'finished'}
                isTie={isLadderTieResult}
              />
            ) : delayingFinalReveal ? (
              <div className="next-question-state final">
                <span>That's the game</span>
                <strong>Final answer locked in</strong>
                <p>Revealing the winner and final places next.</p>
              </div>
            ) : preparingNextQuestion ? (
              <div className={`next-question-state ${isRecoveryQuestion ? 'recovery' : ''}`}>
                <span>{isEliminationLadder ? `Round ${ladderRoundNumber}` : isRecoveryQuestion ? 'Second chance' : 'Next question'}</span>
                <strong>{nextQuestionInSeconds}s</strong>
                <p>
                  {isEliminationLadder
                    ? `Question ${currentAttempt} of ${room.game.questions_per_round || 3} is coming up.`
                    : isRecoveryQuestion
                    ? `${room.active_member?.display_name || 'This player'} can win the points back.`
                    : `${room.active_member?.display_name || 'The next player'} is up next.`}
                </p>
              </div>
            ) : (
              <>
                {isMyTurn && <p className={`player-context ${isRecoveryQuestion || hasSpeedSecondChance ? 'recovery' : ''}`}>{isRecoveryQuestion || hasSpeedSecondChance ? 'Second chance: recover the points' : 'Choose an answer'}</p>}
                {isSpeedRound && !isMyTurn && speedLockedMember && <p className="player-context">{speedLockedMember.display_name}'s second chance</p>}
                {isEliminationLadder && hasAnsweredSharedQuestion && <p className="player-context">Answer locked</p>}
                <h2>{room.question?.prompt || 'No question loaded'}</h2>
                <div className="answer-grid">
                  {room.question &&
                    [
                      ['A', room.question.option_a],
                      ['B', room.question.option_b],
                      ['C', room.question.option_c],
                    ].map(([option, label]) => (
                      <button
                        className="answer-button"
                        disabled={!isMyTurn || answerBusy || preparingNextQuestion}
                        key={option}
                        onClick={() => void submitAnswer(option)}
                        type="button"
                      >
                        <span>{option}</span>
                        {label}
                      </button>
                    ))}
                </div>
                {isSharedQuestionMode && room.speed_round && room.speed_round.answers.length > 0 && (
                  <div className="speed-answer-strip">
                    {room.speed_round.answers.map((answer, index) => (
                      <span className={isEliminationLadder ? 'locked' : answer.is_correct ? 'correct' : 'wrong'} key={answer.id}>
                        {index + 1}. {answer.member_name}
                        {isEliminationLadder ? ' · locked in' : answer.attempt && answer.attempt > 1 ? ` · chance ${answer.attempt}` : ''}
                      </span>
                    ))}
                  </div>
                )}
                {answerMessage && <p className="form-message">{answerMessage}</p>}
                {!isMyTurn && (
                  <p className="empty-state">
                    {isEliminationLadder
                      ? myMember
                        ? hasAnsweredSharedQuestion
                          ? 'Waiting for the rest of the ladder answers.'
                          : 'Get ready for the next ladder question.'
                        : 'This browser has not claimed a player.'
                      : isSpeedRound
                      ? myMember
                        ? speedLockedMember
                          ? `Waiting for ${speedLockedMember.display_name} to take their second chance.`
                          : 'Get ready to buzz in.'
                        : 'This browser has not claimed a player.'
                      : myMember
                        ? `Waiting for ${room.active_member?.display_name || 'the active player'} to answer.`
                        : 'This browser has not claimed a player.'}
                  </p>
                )}
              </>
            )}
          </section>

          <LiveLeaderboard members={room.members} activeMemberId={isSpeedRound ? speedLockedMemberId : room.game.current_member_id} myMemberId={playerIdentity?.memberId || null} />
        </div>
      )}

    </div>
  );
}

function LadderRoundResult({
  roundNumber,
  winner,
  loser,
  seconds,
  isFinal,
  isTie,
}: {
  roundNumber: number;
  winner: GameRoomPayload['members'][number] | null;
  loser: GameRoomPayload['members'][number] | null;
  seconds: number;
  isFinal: boolean;
  isTie: boolean;
}) {
  return (
    <div className={`ladder-round-result ${isTie ? 'tied' : ''}`}>
      <span>Round {roundNumber} complete</span>
      <strong>{isTie ? 'Scores are tied' : winner ? `${winner.display_name} wins the round` : 'Round complete'}</strong>
      <div className="ladder-result-grid">
        <article className="round-winner-card">
          <small>{isTie ? 'Current leader' : 'Round winner'}</small>
          <b>{winner ? winner.display_name : isTie ? 'Still tied' : 'Top score'}</b>
          <em>{winner ? `${winner.points} pts` : 'Scores updated'}</em>
        </article>
        <article className="round-loser-card">
          <small>{isTie ? 'Eliminated' : 'Eliminated'}</small>
          <b>{isTie ? 'No one' : loser ? loser.display_name : 'Lowest score'}</b>
          <em>{isTie ? 'Tie-break question coming up' : loser ? `${loser.points} pts` : 'Out of the ladder'}</em>
        </article>
      </div>
      <p>{isTie ? `Tie-break starts in ${seconds}s.` : isFinal ? 'Final results are coming up.' : `Next round starts in ${seconds}s.`}</p>
    </div>
  );
}

function ConfettiBurst() {
  return (
    <div className="confetti-burst" aria-hidden="true">
      {Array.from({ length: 34 }).map((_, index) => (
        <span
          key={index}
          style={
            {
              '--x': `${((index * 37) % 220) - 110}px`,
              '--y': `${-90 - ((index * 19) % 150)}px`,
              '--r': `${(index * 29) % 360}deg`,
              '--d': `${index * 0.022}s`,
            } as React.CSSProperties
          }
        />
      ))}
    </div>
  );
}

function FinalLeaderboard({ members, winnerId }: { members: GameRoomPayload['members']; winnerId: string | null }) {
  const rankedMembers = [...members].sort((a, b) => b.points - a.points || a.turn_order - b.turn_order);

  return (
    <section className="final-leaderboard-panel">
      <div className="final-leaderboard-header">
        <div>
          <span>Leaderboard</span>
          <h2>Final places</h2>
        </div>
        <strong>{rankedMembers.length} players</strong>
      </div>
      <div className="final-leaderboard-table">
        {rankedMembers.map((member, index) => (
          <article className={`final-leaderboard-row ${member.id === winnerId ? 'winner' : ''}`} key={member.id}>
            <div className="final-place">
              <span>{getOrdinal(index + 1)}</span>
            </div>
            <div>
              <strong>{member.display_name}</strong>
              <span>{member.id === winnerId ? 'Winner' : `Turn ${member.turn_order}`}</span>
            </div>
            <b>{member.points}</b>
          </article>
        ))}
      </div>
    </section>
  );
}

function LiveLeaderboard({
  members,
  activeMemberId,
  myMemberId,
}: {
  members: GameRoomPayload['members'];
  activeMemberId: string | null;
  myMemberId: string | null;
}) {
  const rankedMembers = [...members].sort((a, b) => b.points - a.points || a.turn_order - b.turn_order);
  const leaderId = rankedMembers[0]?.id || null;

  return (
    <aside className="leaderboard-panel">
      <div>
        <p className="eyebrow">Leaderboard</p>
        <h2>Scores</h2>
      </div>
      <div className="leaderboard-list">
        {rankedMembers.map((member, index) => {
          const isLeader = member.id === leaderId;
          const isCurrent = member.id === activeMemberId;
          const isMine = member.id === myMemberId;
          const status = isLeader && isCurrent ? 'Leading · On turn' : isCurrent ? 'On turn' : isLeader ? 'Leading' : member.status;

          return (
            <article
              className={`leaderboard-row ${isLeader ? 'leader' : ''} ${isCurrent ? 'active current' : ''} ${
                isMine ? 'mine' : ''
              }`}
              key={member.id}
            >
              <div className="rank">{index === 0 ? getInitials(member.display_name) : index + 1}</div>
              <div>
                <strong>{member.display_name}</strong>
                <span>
                  {status}
                  {isMine ? ' · You' : ''}
                </span>
              </div>
              <b>{member.points}</b>
            </article>
          );
        })}
      </div>
    </aside>
  );
}

function TimeoutResultToast({ event }: { event: GameRoomPayload['events'][number] }) {
  return (
    <div className="answer-result-toast timeout wrong" role="status" aria-live="polite">
      <div className="answer-result-icon">
        <AlertTriangle size={24} />
      </div>
      <div>
        <strong>Time's up</strong>
        <span>No answer locked in. Points lost.</span>
      </div>
    </div>
  );
}

function AnswerResultToast({ answer }: { answer: NonNullable<GameRoomPayload['latest_answer']> }) {
  const isRecoveryAttempt = (answer.attempt || 1) > 1;
  const result = answer.is_correct ? (isRecoveryAttempt ? 'Recovered' : 'Correct') : 'Wrong';
  const pointText = answer.points_delta !== 0 ? `${answer.points_delta > 0 ? '+' : ''}${answer.points_delta} points` : 'No points change';
  const answerText = answer.is_correct
    ? `You chose ${answer.correct_answer}`
    : `Correct answer: ${answer.correct_answer}`;
  const followUpText = !answer.is_correct && answer.points_delta < 0 && !isRecoveryAttempt ? 'Second chance next' : '';
  const detailParts = [answerText, pointText, followUpText].filter(Boolean);

  return (
    <div className={`answer-result-toast ${answer.is_correct ? 'correct' : 'wrong'}`} role="status" aria-live="polite">
      <div className="answer-result-icon">{answer.is_correct ? <CheckCircle2 size={24} /> : <X size={24} />}</div>
      <div>
        <strong>
          {result}
        </strong>
        <span>{detailParts.join(' · ')}</span>
      </div>
    </div>
  );
}

function getInitials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');
}

function getOrdinal(value: number) {
  const suffix = value % 100 >= 11 && value % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][value % 10] || 'th';
  return `${value}${suffix}`;
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
