create or replace function delta_compute_java_method_args(p_idkey integer ,p_idshortnam character varying(2000),p_args character varying(500))
Returns void as 
$body$
declare
l_pos integer := 0;
l_args character varying(500);
begin
  l_pos := strpos(p_args,',');
  if (l_pos > 0) then
    insert into delta_java_method_args values (p_idkey,p_idshortnam,substr(p_args,1,l_pos - 1));
    l_args := substr(p_args,l_pos + 1);
    perform delta_compute_java_method_args (p_idkey,p_idshortnam,l_args);
  else
    insert into delta_java_method_args values (p_idkey,p_idshortnam,substr(p_args,1,length(p_args) - 1));
  end if;
  Return;
End;
$body$ 
LANGUAGE 'plpgsql';

create or replace function delta_compute_java_method()
Returns void as 
$body$
declare
cursor_method RECORD;
begin
  truncate table delta_java_method;
  truncate table delta_java_method_args;
  truncate table delta_java_projects;
  truncate table delta_java_dependencies;
  
  --computation
  insert into delta_java_method(idkey,idshortnam,args)
  select idkey,idshortnam,substr(idshortnam ,strpos(idshortnam,'(') + 1)
  from objects o
  where objtyp = 102
  and exists (select 1 from keys k where k.idkey = o.idkey)
  and length(substr(idshortnam ,strpos(idshortnam,'('))) > 2
  and strpos(substr(idshortnam ,strpos(idshortnam,'(')),'99?') = 0;

  For cursor_method In select idkey,idshortnam,args from delta_java_method where length(args) > 1
  Loop
    perform delta_compute_java_method_args (cursor_method.idkey,cursor_method.idshortnam,cursor_method.args);
  end loop;
  delete from delta_java_method_args where arg in ('boolean','int','int[]','long','float','string','byte','byte[]','short','double','char','char[]');
  delete from delta_java_method_args where strpos(arg,'.') > 0;

  insert into delta_java_projects (idpro,pronam)
  select distinct op.idpro,p.keynam
  from delta_java_method m
   join objpro op on (op.idobj = m.idkey and op.prop = 0)
   join keys p on (p.idkey = op.idpro)
  where length(args) > 0;

  insert into delta_java_dependencies(idpro,pronam,idprodep,prodepnam)
  select distinct p.idpro,p.pronam,d.idpro,pd.keynam
  from delta_java_projects p
   join objpro op on (op.idpro = p.idpro and op.prop = 0)
   join delta_java_method_args m on (m.idkey = op.idobj)
   join keys c on (c.objtyp = 100 and c.keynam = m.arg)
   join objpro d on (d.idobj = c.idkey and d.prop = 0)
   join keys pd on (pd.idkey = d.idpro);

  Return;
End;
$body$ 
LANGUAGE 'plpgsql';

select delta_compute_java_method();
