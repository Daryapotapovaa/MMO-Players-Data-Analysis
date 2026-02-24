-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Найдем общее количество пользователей, количество платящих пользователей и их долю от общего количества
SELECT
	COUNT(*) AS user_count,
	SUM(payer) AS paying_user_count,
	ROUND(AVG(payer), 3) AS paying_user_perc
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- Найдем общее количество пользователей, количество платящих пользователей и их долю от общего количества для каждой расы
SELECT
	r.race_id,
	r.race,
	COUNT(u.id) AS user_count,
	SUM(u.payer) AS paying_user_count,
	ROUND(AVG(u.payer), 3) AS paying_user_perc
FROM fantasy.users AS u
JOIN fantasy.race AS r ON u.race_id = r.race_id 
GROUP BY r.race_id, r.race;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Найдем суммарное, максимальное, минимальное и среднее значение стоимости покупки, а ее медиану и стандартное отклонение 
SELECT 
	COUNT(*) AS buy_count,
	SUM(amount) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	AVG(amount) AS avg_amount,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS median_amont,
	STDDEV(amount) AS std_amount
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
-- Минимальная стоимость покупки оказалась нулевой, найдем количество и долю таких покупок
SELECT 
	COUNT(transaction_id) AS zero_cost_buy_count,
	COUNT(transaction_id) / (SELECT COUNT(*) FROM fantasy.events)::NUMERIC AS zero_cost_buy_perc
FROM fantasy.events
WHERE amount = 0;

-- 2.3: Популярные эпические предметы:
-- Найдем общее количество внутриигровых продаж в абсолютном и относительном значениях, а также долю игроков, которые хотя бы раз покупали этот предмет
SELECT 
	i.item_code,
	i.game_items,
	COUNT(e.transaction_id) AS sale_count,
	COUNT(e.transaction_id) / (SELECT COUNT(*) FROM fantasy.events WHERE amount <> 0)::NUMERIC AS sale_perc,
	COUNT(DISTINCT e.id) AS unique_buyer_count,
	COUNT(DISTINCT e.id) / (SELECT COUNT(DISTINCT id) FROM fantasy.events WHERE amount <> 0)::NUMERIC AS buyer_perc
FROM fantasy.items AS i
LEFT JOIN fantasy.events AS e ON i.item_code = e.item_code
WHERE e.amount <> 0
GROUP BY i.item_code, i.game_items
ORDER BY sale_count DESC;

-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа:
-- Для каждой расы найдем общее количество зарегистрированных игроков
WITH race_user_count AS(
	SELECT
		r.race_id,
		r.race,
		COUNT(id) AS total_user_count
	FROM fantasy.race AS r
	LEFT JOIN  fantasy.users AS u ON r.race_id = u.race_id 
	GROUP BY r.race_id, r.race
),
-- Для каждой расы найдем количество игроков, совершавших покупки и долю платящих среди них
race_pay_user_stat AS(
	SELECT 
		race_id,
		COUNT(id) AS buyer_count,
		SUM(payer) / COUNT(id)::NUMERIC AS paying_buyer_perc
	FROM fantasy.users
	WHERE id IN (SELECT DISTINCT id FROM fantasy.events WHERE amount <> 0)
	GROUP BY race_id
),
-- Для каждой расы найдем среднее количество покупок на одного игрока, 
--                        среднюю стоимость одной покупки на одного игрока, 
--                        а также среднюю суммарную стоимость покупок на одного игрока
race_user_activity AS(
	SELECT 
		u.race_id,
		AVG(bc.buy_count) AS race_avg_buy_count,
		AVG(bc.avg_amount) AS race_avg_one_buy_cost,
		AVG(bc.sum_amount) AS race_avg_sum_buy_cost
	FROM (
		SELECT
			id,
			COUNT(transaction_id) AS buy_count,
			AVG(amount) AS avg_amount,
			SUM(amount) AS sum_amount
		FROM fantasy.events
		WHERE amount <> 0
		GROUP BY id
	) AS bc
	LEFT JOIN fantasy.users AS u ON bc.id = u.id
	GROUP BY u.race_id
)
SELECT
	us.race_id,
	c.race,
	c.total_user_count,
	us.buyer_count,
	us.buyer_count / c.total_user_count::NUMERIC AS buyer_count_perc,
	us.paying_buyer_perc,
	ua.race_avg_buy_count,
	ua.race_avg_one_buy_cost,
	ua.race_avg_sum_buy_cost 
FROM race_user_count AS c
JOIN race_pay_user_stat AS us ON c.race_id = us.race_id
JOIN race_user_activity AS ua ON us.race_id = ua.race_id
ORDER BY buyer_count_perc;
