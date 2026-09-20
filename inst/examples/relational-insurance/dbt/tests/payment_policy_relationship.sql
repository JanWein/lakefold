select payments.payment_id
from {{ source('inputs', 'payments') }} as payments
left join {{ source('inputs', 'policies') }} as policies
  using (policy_id, month)
where policies.policy_id is null
   or payments.company <> policies.company
   or payments.channel <> policies.channel
   or payments.month <> cast(date_trunc('month', payments.payment_date) as date)
