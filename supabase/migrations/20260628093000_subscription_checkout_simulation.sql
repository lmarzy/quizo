alter table public.subscriptions
add column if not exists billing_interval text check (billing_interval in ('monthly', 'quarterly', 'yearly')),
add column if not exists billing_amount_cents integer check (billing_amount_cents is null or billing_amount_cents >= 0),
add column if not exists currency text default 'gbp';

create or replace function public.set_test_subscription_checkout(
  p_plan_id text,
  p_billing_interval text
)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  amount_cents integer;
  period_end timestamptz;
  sub_record public.subscriptions;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to change plan.';
  end if;

  if p_plan_id not in ('free', 'pro', 'creator') then
    raise exception 'Unsupported test plan.';
  end if;

  if p_billing_interval not in ('monthly', 'quarterly', 'yearly') then
    raise exception 'Unsupported billing interval.';
  end if;

  amount_cents := case
    when p_plan_id = 'free' then 0
    when p_plan_id = 'pro' and p_billing_interval = 'monthly' then 699
    when p_plan_id = 'pro' and p_billing_interval = 'quarterly' then 1799
    when p_plan_id = 'pro' and p_billing_interval = 'yearly' then 5999
    when p_plan_id = 'creator' and p_billing_interval = 'monthly' then 1499
    when p_plan_id = 'creator' and p_billing_interval = 'quarterly' then 3999
    when p_plan_id = 'creator' and p_billing_interval = 'yearly' then 12999
    else null
  end;

  period_end := case
    when p_plan_id = 'free' then null
    when p_billing_interval = 'monthly' then now() + interval '1 month'
    when p_billing_interval = 'quarterly' then now() + interval '3 months'
    when p_billing_interval = 'yearly' then now() + interval '1 year'
    else null
  end;

  insert into public.subscriptions (
    user_id,
    plan_id,
    status,
    stripe_customer_id,
    stripe_subscription_id,
    stripe_price_id,
    current_period_end,
    cancel_at_period_end,
    billing_interval,
    billing_amount_cents,
    currency
  )
  values (
    auth.uid(),
    p_plan_id,
    case
      when p_plan_id = 'free' then 'free'::public.subscription_status
      else 'active'::public.subscription_status
    end,
    null,
    null,
    null,
    period_end,
    false,
    case when p_plan_id = 'free' then null else p_billing_interval end,
    amount_cents,
    'gbp'
  )
  on conflict (user_id) do update
  set
    plan_id = excluded.plan_id,
    status = excluded.status,
    stripe_customer_id = null,
    stripe_subscription_id = null,
    stripe_price_id = null,
    current_period_end = excluded.current_period_end,
    cancel_at_period_end = false,
    billing_interval = excluded.billing_interval,
    billing_amount_cents = excluded.billing_amount_cents,
    currency = excluded.currency,
    updated_at = now()
  returning * into sub_record;

  return sub_record;
end;
$$;

grant execute on function public.set_test_subscription_checkout(text, text) to authenticated;
