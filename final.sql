WITH users_parsed AS (
    /*
    - CTE #1
    - Очищення та нормалізація дат реєстрації користувачів
    - Мета: отримати коректну дату signup_ts у форматі YYYY-MM-DD
    - БЕЗ ВКЛАДЕНИХ ЗАПИТІВ!
    */
    SELECT
        user_id,
        signup_datetime,
        promo_signup_flag,
        -- Виділяємо лише дату (без часу) та замінюємо роздільники
        CASE 
            WHEN signup_datetime IS NULL THEN NULL
            ELSE 
                TO_DATE(
                    CASE 
                        -- Якщо рік 2-значний (наприклад, 25)
                        WHEN LENGTH(SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 3)) = 2 
                            THEN '20' || SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 3)
                        -- Якщо рік 4-значний
                        ELSE SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 3)
                    END || '-' ||
                    LPAD(SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 2), 2, '0') || '-' ||
                    LPAD(SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 1), 2, '0'),
                    'YYYY-MM-DD'
                )
        END AS signup_ts
    FROM cohort_users_raw
),
events_parsed AS (
    /*
    - CTE #2
    - Очищення та нормалізація дат подій користувачів
    - Так само БЕЗ ВКЛАДЕНИХ ЗАПИТІВ!
    */
    SELECT
        user_id,
        event_type,
        event_datetime,
        CASE 
            WHEN event_datetime IS NULL THEN NULL
            ELSE 
                TO_DATE(
                    CASE 
                        -- Якщо рік 2-значний
                        WHEN LENGTH(SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 3)) = 2 
                            THEN '20' || SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 3)
                        -- Якщо рік 4-значний
                        ELSE SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 3)
                    END || '-' ||
                    LPAD(SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 2), 2, '0') || '-' ||
                    LPAD(SPLIT_PART(REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-'), '-', 1), 2, '0'),
                    'YYYY-MM-DD'
                )
        END AS event_ts
    FROM cohort_events_raw
),
user_activity AS (
    /*
    - CTE #3
    - Обʼєднання користувачів і подій
    - Формування когорт і розрахунок month_offset
    */
    SELECT
        u.user_id,
        u.promo_signup_flag,
        -- Місяць реєстрації користувача (когорта)
        DATE_TRUNC('month', u.signup_ts)::DATE AS cohort_month,
        -- Місяць активності користувача
        DATE_TRUNC('month', e.event_ts)::DATE AS activity_month,
        -- Кількість місяців між реєстрацією та активністю
        EXTRACT(
            MONTH FROM AGE(
                DATE_TRUNC('month', e.event_ts),
                DATE_TRUNC('month', u.signup_ts)
            )
        ) AS month_offset
    FROM users_parsed u
    JOIN events_parsed e
        ON u.user_id = e.user_id
    WHERE
        -- Відкидання некоректних записів
        u.signup_ts IS NOT NULL
        AND e.event_ts IS NOT NULL
        -- Виключаємо події без типу
        AND e.event_type IS NOT NULL
        -- Прибирання тестових подій
        AND e.event_type <> 'test_event'
)
-- ФІНАЛЬНИЙ SELECT (агрегована когортна таблиця)
SELECT
    promo_signup_flag,
    TO_CHAR(cohort_month, 'YYYY-MM-DD') AS cohort_month,
    month_offset,
    COUNT(DISTINCT user_id) AS users_total
FROM user_activity
WHERE
    -- Обмеження періоду активності з січня по червень 2025
    activity_month BETWEEN DATE '2025-01-01' AND DATE '2025-06-01'
GROUP BY
    promo_signup_flag,
    cohort_month,
    month_offset
ORDER BY
    promo_signup_flag,
    cohort_month,
    month_offset;