-- Both parents now have one row per company, channel and month.
select
  policies.company,
  policies.channel,
  policies.month,
  policies.active_policies,
  policies.premium_due,
  cast(coalesce(cash.payment_count, 0) as integer) as payment_count,
  cast(coalesce(cash.cash_collected, 0) as double) as cash_collected
from {{ ref('core_policy_monthly') }} as policies
left join {{ ref('core_cash_monthly') }} as cash
  using (company, channel, month)
