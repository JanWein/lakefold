-- Aggregate the policy-month grain without joining individual payments.
select
  company,
  channel,
  month,
  cast(sum(case when status = 'active' then 1 else 0 end) as integer) as active_policies,
  cast(sum(premium_due) as double) as premium_due
from {{ source('inputs', 'policies') }}
group by company, channel, month
