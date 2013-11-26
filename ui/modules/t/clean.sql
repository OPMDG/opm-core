-- Create needes roles
SELECT public.drop_user('selenium_simpleuser');
SELECT public.drop_user('selenium_superuser');
SELECT public.drop_account('selenium_acc');
DROP ROLE selenium_simpleuser;
DROP ROLE selenium_sueruser;
DROP ROLE selenium_acc;

WITH list_graph (id) AS (
    DELETE FROM pr_grapher.graph_wh_nagios g
        USING wh_nagios.labels l
        WHERE g.id_label = l.id
        AND l.label like 'selenium%'
    RETURNING g.id_graph)
DELETE FROM pr_grapher.graphs g
    USING list_graph l
    WHERE g.id = l.id;

DELETE FROM public.services WHERE service like 'selenium%';
DELETE FROM public.servers WHERE hostname like 'selenium%';

