-- Create needes roles
SELECT public.create_account('selenium_acc');
SELECT public.create_user('selenium_simpleuser','password','{selenium_acc}');
SELECT public.create_user('selenium_superuser','password','{opm_admins}');

-- Insert some data
INSERT INTO wh_nagios.hub SELECT i,('{MIN,0,MAX,10000,WARNING,1000,CRITICAL,5000,HOSTNAME,selenium_server_1,LABEL,selenium_label_1,UOM,B,SERVICESTATE,OK,SERVICEDESC,selenium_service_1,TIMET,' || (extract(epoch FROM now() - '3 month'::interval)+(i*60*5)) || ',VALUE, ' || i % 100 || '}')::text[] FROM generate_series(1,60/5*24*31*3) i;

SELECT * from wh_nagios.dispatch_record(true);

SELECT pr_grapher.create_graph_for_wh_nagios(s.id)
FROM (
    SELECT id
    FROM public.servers
    WHERE hostname like 'selenium%'
) s;
