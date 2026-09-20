with policy_input as (
  select month,
    sum(case when status = 'active' then 1 else 0 end) as active_policies,
    sum(premium_due) as premium_due
  from {{ source('inputs', 'policies') }}
  group by month
), cash_input as (
  select month, count(*) as payment_count, sum(cash_amount) as cash_collected
  from {{ source('inputs', 'payments') }}
  group by month
), reported as (
  select month, sum(active_policies) as active_policies, sum(premium_due) as premium_due,
    sum(payment_count) as payment_count, sum(cash_collected) as cash_collected
  from {{ ref('monthly_performance') }}
  group by month
)
select coalesce(policy_input.month, reported.month) as month
from policy_input
full outer join reported using (month)
left join cash_input using (month)
where policy_input.month is null or reported.month is null
  or reported.active_policies <> policy_input.active_policies
  or abs(reported.premium_due - policy_input.premium_due) > 0.000001
  or reported.payment_count <> coalesce(cash_input.payment_count, 0)
  or abs(reported.cash_collected - coalesce(cash_input.cash_collected, 0)) > 0.000001
