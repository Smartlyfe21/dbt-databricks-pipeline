{% macro parse_salary(column_name, bound) %}
    {% set position = 1 if bound == 'min' else -1 %}
    {% set segment = "ELEMENT_AT(SPLIT(" ~ column_name ~ ", '–'), " ~ position ~ ")" %}

    TRY_CAST(
        REPLACE(
            REGEXP_EXTRACT({{ segment }}, '([0-9][0-9,.]*)', 1),
            ',', ''
        ) AS DECIMAL(15, 2)
    ) * CASE UPPER(REGEXP_EXTRACT({{ segment }}, '[0-9][0-9,.]*([KkMm])', 1))
            WHEN 'K' THEN 1000
            WHEN 'M' THEN 1000000
            ELSE 1
        END
{% endmacro %}


