drop table if exists cancel_classification;
-- 68 sec
create temp table cancel_classification as 

with ivr_calls as (
	select distinct on (order_id)
		order_id,
		perform_at,
		status,
		result
	from order_reminders
	order by order_id, perform_at desc
), unpacked_deltas as (
	select
		user_id,
		model_id as order_id,
		json_array_elements(object)->>'name' as field_name,
		json_array_elements(object)->>'object'  as field_value,
		created_at
	from deltas
	where  model_type='Order'
		and model_id in (select id from orders where deal_id is null and workflow_state in ('paid', 'canceled'))
), logged_cancelations as (
	select
		*
	from unpacked_deltas
	where field_name = 'workflow_state'
		and field_value = 'canceled'
), crm_cancellations as (
	select 
		subject_id as order_id
	from diffs, jsonb_each(differences) 
	where subject_type='Order'
		and key = 'workflow_state'
		and value::text like '%canceled%'
), sub_cancelations as (
	select
		o.id as order_id,
		subscription_id,
		rank() over (PARTITION BY subscription_id ORDER BY start_at DESC) as sub_cancel_num
	from subscriptions s
		left join orders o on (s.id = o.subscription_id and o.canceled_at >= s.deactivated_at)
	where s.deactivated_at is not null
		and o.workflow_state = 'canceled'
), cancel_classification_tmp as (
	select
		o.id as order_id,
		case
			when creation_mean = 'auto' and (canceled_at - o.created_at) between interval '0 minutes' and interval '10 minutes' then 'trash_autosubscr'
			when status = 'failed' and (canceled_at - perform_at) between interval '0 minutes' and interval '10 minutes' then 'ivr-auto'
			when status = 'success' and result = 'order_canceled' and (canceled_at - perform_at) between interval '0 minutes' and interval '10 minutes' then 'ivr-user'
			when status = 'success' and result = 'handled_by_call_center' and (canceled_at - perform_at) between interval '0 minutes' and interval '10 minutes' then 'ivr-cc'
			when o.subscription_id is null then 'one-time'
			when date(deactivated_at) = date(canceled_at) and sc.sub_cancel_num = 1 then 'subscr_cancel'
			when date(deactivated_at) = date(canceled_at) then 'trash_subscr'
			when date(deactivated_at) > date(canceled_at) and o.subscription_id is not null then 'part-subscr'
			when deactivated_at is null and o.subscription_id is not null then 'part-subscr'
			else 'unknown'
		end as cancel_type
	from orders o
		left join subscriptions s on (o.subscription_id = s.id)
		left join ivr_calls i on (o.id = i.order_id)
		left join logged_cancelations c on (o.id = c.order_id)
		left join users_roles r on (c.user_id = r.user_id)
		left join crm_cancellations crm on (o.id = crm.order_id)
		left join sub_cancelations sc on (o.id = sc.order_id)
	where confirmed_at is not null
		and workflow_state = 'canceled'
		and deal_id is null
)

select * from cancel_classification_tmp;


with constants as (
	select
		'2017-07-07'::date as start_date,
		'2017-08-08'::date as end_date 
		--'2017-06-20'::date as start_date, -- VALIDATION
		--'2017-07-04'::date as end_date -- VALIDATION
), orders_recency_info as (
	select
		o1.user_id,
		o1.id as order_id,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and o2.checked_out_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_all,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and date(o1.start_at) - date(o2.checked_out_at) < 16
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_16d,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and date(o1.start_at) - date(o2.checked_out_at) < 30
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_30d,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and date(o1.start_at) - date(o2.checked_out_at) < 60
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_60d,
		-- canceled	
		count(distinct o2.id) filter (where o2.workflow_state = 'canceled' 
			and o2.canceled_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type not like 'trash%') as canceled_all_nt,
			
		count(distinct o2.id) filter (where o2.workflow_state = 'canceled' 
			and date(o1.start_at) - date(o2.canceled_at) < 16
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type not like 'trash%') as canceled_16d_nt,
			
		count(distinct o2.id) filter (where o2.workflow_state = 'canceled' 
			and date(o1.start_at) - date(o2.canceled_at) < 30
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type not like 'trash%') as canceled_30d_nt,
			
		count(distinct o2.id) filter (where o2.workflow_state = 'canceled' 
			and date(o1.start_at) - date(o2.canceled_at) < 60
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type not like 'trash%') as canceled_60d_nt,
		
			
		count(distinct o2.id) filter (where o2.workflow_state = 'canceled' 
			and o2.canceled_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type = 'one-time') as canceled_onetime_nt,
					
		min(date(o1.start_at)-date(o2.canceled_at)) filter (where o2.workflow_state = 'canceled' 
			and o2.canceled_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type not like 'trash%') as days_since_last_cancel_all_nt,
			
		min(date(o1.start_at)-date(o2.canceled_at)) filter (where o2.workflow_state = 'canceled' 
			and o2.canceled_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type = 'one-time') as days_since_last_cancel_onetime_nt,
			
		min(date(o1.start_at)-date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and o2.start_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null) as days_since_last_paid_order,
		-- можно еще добавить среднее время между уборками: max - min / cnt
		-- fill_na не 0 должно быть
		min(date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and o2.start_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null) as first_order_dt,
		
		max(date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and o2.start_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null) as last_order_dt
		
	from orders o1
		left join orders o2 on (o1.user_id = o2.user_id and o2.start_at < o1.start_at)
		left join cancel_classification c on (o2.id = c.order_id)
	where o1.deal_id is null
		and o1.confirmed_at is not null
		-- and o1.workflow_state != 'canceled'
		and o1.workflow_state in ('paid', 'canceled')
		and (o1.canceled_at is null or date(o1.start_at) - date(o1.canceled_at) < 7) -- это чтобы вычистить ненужные отмены, чтобы на мусоре не тренировать
		and o1.workflow_state != 'hidden'
		and o1.start_at >= (select start_date from constants)
		and o1.start_at < (select end_date from constants)
		
	group by 1,2
	order by 2
), orders_general_info as (
	select
		o.id as order_id,
		o.total_cents,
		o.subtotal_cents,
		o.subtotal_cents - o.total_cents as discount,
		case when o.subtotal_cents != 0 then (o.subtotal_cents - o.total_cents)/o.subtotal_cents::float else 1 end as discount_prc,
		--o.payment_type, -- ohc
		case when o.payment_type = 'cash' then 1 else 0 end as cash_flg,
		--o.creation_mean, -- ohc
		case when o.creation_mean = 'auto' then 1 else 0 end as auto_flg,
		extract(dow from start_at) as dow, -- ohc
		case when hot then 1 else 0 end as hot,
		
		(case when refrigerator then 1 else 0 end
			+ case when oven then 1 else 0 end
			+ case when windows > 0 then 1 else 0 end
			+ case when ironing > 0 then 1 else 0 end
			+ case when kitchen_cabinets then 1 else 0 end
			+ case when tableware then 1 else 0 end
			+ case when balconies > 0 then 1 else 0 end
			+ case when microwave then 1 else 0 end
			+ case when keys_delivery then 1 else 0 end
			+ case when consumables_and_equipment then 1 else 0 end
			+ case when shower then 1 else 0 end
			+ case when bedlinen then 1 else 0 end
			+ case when cat_litter_box > 0 then 1 else 0 end
			+ case when lustre > 0 then 1 else 0 end
			+ case when wardrobe then 1 else 0 end) as additionals_num,
	
		-- Start Time
		--case when extract(hour from start_at) < 8 then 1 else 0 end morning_slot,
		case when extract(hour from start_at) between 8 and 12 then 1 else 0 end day_slot_flg,
		--case when extract(hour from start_at) >= 13 then 1 else 0 end evening_slot,
		
		-- o.type, -- ohc
		case when o.notice is not null then 1 else 0 end as has_comment,
		case when o.subscription_id is not null then 1 else 0 end as subscription_flg,
		a.lat,
		a.lng,
		round(EXTRACT(epoch FROM (o.start_at - o.created_at))/3600) as creation_start_hours,
		
		-- TARGET
		case when canceled_at is not null then 1 else 0 end as cancel
	from orders o
		left join addresses a on (o.address_id = a.id)
	where deal_id is null
		and confirmed_at is not null
		-- and workflow_state != 'canceled'
		and workflow_state in ('paid', 'canceled')
		and workflow_state != 'hidden'
		and (canceled_at is null or date(start_at) - date(canceled_at) < 7) -- это чтобы вычистить ненужные отмены, чтобы на мусоре не тренировать
		and start_at >= (select start_date from constants)
		and start_at < (select end_date from constants)
), order_deltas as (
	select 
		model_id as order_id,
		json_array_elements(object)->>'name' as field_name,
		json_array_elements(object)->>'object'  as field_value,
		created_at
	from deltas
	where model_type='Order'
		and model_id in (select order_id from orders_general_info)
), order_shifts as (
	select
		order_id,
		count(order_id)-1 as shifts_num
	from order_deltas
	where field_name = 'start_at'
	group by 1
), dow_cleanings as (

	select
		o1.user_id,
		o1.id as order_id,
		extract(dow from o1.start_at) as dow,
		count(o2.id) filter (where o2.workflow_state = 'paid' 
			and o2.checked_out_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and extract(dow from o2.start_at) = extract(dow from o1.start_at)) as dow_paid,
		count(o2.id) filter (where o2.workflow_state = 'canceled' 
			and o2.canceled_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null
			and c.cancel_type not like 'trash%'
			and extract(dow from o2.start_at) = extract(dow from o1.start_at)) as dow_canceled
	from orders o1
		left join orders o2 on (o1.user_id = o2.user_id and o2.start_at < o1.start_at)
		left join cancel_classification c on (o2.id = c.order_id)
	where o1.deal_id is null
		and o1.confirmed_at is not null
		--and o1.workflow_state != 'canceled'
		and o1.workflow_state in ('paid', 'canceled')
		and (o1.canceled_at is null or date(o1.start_at) - date(o1.canceled_at) < 7) -- это чтобы вычистить ненужные отмены, чтобы на мусоре не тренировать
		and o1.workflow_state != 'hidden'
		and o1.start_at >= (select start_date from constants)
		and o1.start_at < (select end_date from constants)
		
	group by 1,2,3
), trackings as (
	select * from dblink('dbname=snowplow', E'
		select distinct
			json_extract_path_text(contexts,\'tracking_id\') as tracking_id,
			user_id
		from atomic.events
		where collector_tstamp > \'2017-07-01\'
			and app_id = \'qlean_web_app\'
			and user_id is not null
			and json_extract_path_text(contexts,\'tracking_id\') is not null') t (tracking_id varchar(64), user_id int)
), aidata_segments as (
	select * from dblink('dbname=snowplow', E'
		select distinct on (tracking_id)
			tracking_id,
			segments
		from uploads.aidata_segments
		order by tracking_id, date desc') t (tracking_id varchar(64), segments text)
)

select 
	g.*,
	r.paid_all,
	r.canceled_all_nt,
	case when r.canceled_all_nt != 0  then r.canceled_all_nt/(r.paid_all + r.canceled_all_nt)::float else 0 end as canceled_all_nt_share,
	paid_16d,
	paid_30d,
	paid_60d,
	r.canceled_16d_nt,
	r.canceled_30d_nt,
	r.canceled_60d_nt,
	shifts_num, -- fill_na
	
	canceled_onetime_nt,
	days_since_last_cancel_all_nt,
	days_since_last_cancel_onetime_nt,

	days_since_last_paid_order,
	dow_paid,
	dow_canceled,
	case when (dow_canceled + dow_paid) != 0 then dow_paid/(dow_canceled + dow_paid)::float end as dow_paid_share,
	case when r.paid_all != 0 then dow_paid/r.paid_all::float end as dow_all_paid_share,
	--t.tracking_id,
	ai.segments
	
from orders_general_info g
	left join orders_recency_info r on (g.order_id = r.order_id)
	left join order_shifts s on (g.order_id = s.order_id)
	left join dow_cleanings c on (g.order_id = c.order_id and g.dow = c.dow)
	left join trackings t on (c.user_id = t.user_id)
	left join aidata_segments ai on (t.tracking_id = ai.tracking_id);