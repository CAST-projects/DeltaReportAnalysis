create or replace FUNCTION delta_analyis_report_before ()
RETURNS void as
$body$
declare
L_ID integer := 0;
Begin
  select COALESCE(max(ID)+1,1)
  into L_ID
  from DELTA_REPORT;

  insert into DELTA_REPORT (ID,TAG)
  select L_ID
    , (select 'Upgrade to ' || pv.version || ' at ' || current_timestamp(0) from sys_package_version pv where package_name = 'BASE_LOCAL');

  perform delta_analyis_report(L_ID,'B');
End;
$body$ 
LANGUAGE plpgsql;

create or replace FUNCTION delta_analyis_report_after ()
RETURNS void as
$body$
declare
L_ID integer := 0;
Begin
  select COALESCE(max(ID),0)
  into L_ID
  from DELTA_REPORT
  where TAG like (select 'Upgrade to ' || pv.version || '%' from sys_package_version pv where package_name = 'BASE_LOCAL');

  if (L_ID > 0) then
    delete from DELTA_ID where ID = L_ID and TYPE in ('A','M');
    delete from DELTA_OBJECT where ID = L_ID and TYPE in ('A','M');
    delete from DELTA_PROPS where ID = L_ID and TYPE in ('A','M');
    delete from DELTA_PROPN where ID = L_ID and TYPE in ('A','M');
    delete from DELTA_LINK where ID = L_ID and TYPE in ('A','M');
    delete from DELTA_DYNLINK where ID = L_ID and TYPE in ('A','M');
    perform delta_analyis_report(L_ID,'A');
    perform delta_analyis_report(L_ID,'M');
    
    perform delta_analyis_report_diff(L_ID);
  end if;
End;
$body$ 
LANGUAGE plpgsql;

create or replace FUNCTION delta_analyis_report (p_id integer, p_delta_type character varying)
RETURNS void as
$body$
declare
L_ID_MAX integer := 0;
Begin
  if (p_delta_type <> 'M') then  
    insert into DELTA_ID (ID,TYPE,NAME,VALUE)
    select p_id,p_delta_type,'idkey',max(idkey) from keys;

    insert into DELTA_ID (ID,TYPE,NAME,VALUE)
    select p_id,p_delta_type,'idacc',max(idacc) from acc;

    select max(idkey)
    into L_ID_MAX
    from keys;
  else
    select VALUE
    into L_ID_MAX
    from DELTA_ID
    where ID = p_id and TYPE = 'B' and NAME = 'idkey';
  end if;
  
  truncate table DELTA_WK_OBJECT;
  
  insert into DELTA_WK_OBJECT (OBJECT_TYPE,VALUE)
  select k.objtyp,count(1)
  from keys k
  where k.idkey <= L_ID_MAX
  and exists (select 1 from objpro op where op.idobj = k.idkey)
  group by k.objtyp;

  insert into DELTA_OBJECT (ID,TYPE,OBJECT_TYPE,VALUE,OBJECT_TYPE_STR,LANGUAGE)
  select p_id,p_delta_type,o.OBJECT_TYPE,o.VALUE,t.objtypstr,t.lngstr
  from DELTA_WK_OBJECT o
    join objtypstr t on (t.objtyp = o.OBJECT_TYPE);

  truncate table DELTA_WK_PROPS;
  
  insert into DELTA_WK_PROPS (OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE)
  select k.objtyp,T1.inftyp,T1.infsubtyp,count(1)
  from keys k
    join objdsc T1 on (T1.idobj = k.idkey)
  where k.idkey <= L_ID_MAX
  and exists (select 1 from objpro op where op.idobj = k.idkey)
  group by k.objtyp,T1.inftyp,T1.infsubtyp;

  insert into DELTA_PROPS (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select p_id,p_delta_type,o.OBJECT_TYPE,o.PROP_TYPE,o.PROP_SUB_TYPE,o.VALUE,t.objtypstr,d.dsc,t.lngstr
  from DELTA_WK_PROPS o
    join objtypstr t on (t.objtyp = o.OBJECT_TYPE)
    join objdscref d on (d.inftyp = o.PROP_TYPE and d.infsubtyp = o.PROP_SUB_TYPE);
   
  truncate table DELTA_WK_PROPN;
  
  perform droptemporarytable('delta_wk_propn_excluded');
  create temporary table DELTA_WK_PROPN_EXCLUDED (OBJECT_TYPE integer,PROP_TYPE integer,PROP_SUB_TYPE integer) with (autovacuum_enabled=false);
  insert into DELTA_WK_PROPN_EXCLUDED (OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE) 
  select k.objtyp,T1.inftyp,T1.infsubtyp
  from keys k
    join objinf T1 on (T1.idobj = k.idkey)
  where k.idkey <= L_ID_MAX
  and not ((T1.inftyp = 3 and T1.infsubtyp = 0) or (T1.inftyp = 4 and T1.infsubtyp = 0))
  and exists (select 1 from objpro op where op.idobj = k.idkey)
  group by k.objtyp,T1.inftyp,T1.infsubtyp
  having sum(T1.infval) > 2147483647 or sum(T1.infval) < -2147483648;
   
  insert into DELTA_WK_PROPN (OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL)
  select k.objtyp,T1.inftyp,T1.infsubtyp,count(1),0 -- sum is higher or lower than max value for integer
  from keys k
    join objinf T1 on (T1.idobj = k.idkey)
    join DELTA_WK_PROPN_EXCLUDED T2 on (T2.OBJECT_TYPE = k.objtyp and T2.PROP_TYPE = T1.inftyp and T2.PROP_SUB_TYPE = T1.infsubtyp)
  where k.idkey <= L_ID_MAX
  and not ((T1.inftyp = 3 and T1.infsubtyp = 0) or (T1.inftyp = 4 and T1.infsubtyp = 0))
  and exists (select 1 from objpro op where op.idobj = k.idkey)
  group by k.objtyp,T1.inftyp,T1.infsubtyp;
  
  insert into DELTA_WK_PROPN (OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL)
  select k.objtyp,T1.inftyp,T1.infsubtyp,count(1),sum(T1.infval)
  from keys k
    join objinf T1 on (T1.idobj = k.idkey)
  where k.idkey <= L_ID_MAX
  and not ((T1.inftyp = 3 and T1.infsubtyp = 0) or (T1.inftyp = 4 and T1.infsubtyp = 0))
  and exists (select 1 from objpro op where op.idobj = k.idkey)
  and not exists (select 1 from DELTA_WK_PROPN_EXCLUDED T2 where T2.OBJECT_TYPE = k.objtyp and T2.PROP_TYPE = T1.inftyp and T2.PROP_SUB_TYPE = T1.infsubtyp)
  group by k.objtyp,T1.inftyp,T1.infsubtyp;

  perform droptemporarytable('delta_wk_propn_excluded');
  
  insert into DELTA_PROPN (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select p_id,p_delta_type,o.OBJECT_TYPE,o.PROP_TYPE,o.PROP_SUB_TYPE,o.VALUE,o.TOTAL,t.objtypstr,d.dsc,t.lngstr
  from DELTA_WK_PROPN o
    join objtypstr t on (t.objtyp = o.OBJECT_TYPE)
    join objdscref d on (d.inftyp = o.PROP_TYPE and d.infsubtyp = o.PROP_SUB_TYPE);


  truncate table DELTA_WK_LINK;
  
  insert into DELTA_WK_LINK (CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE)
  select k1.objtyp,a.acctyplo,a.acctyphi,k2.objtyp,count(1)
  from keys k1
    join acc a on (a.idclr = k1.idkey and a.accknd = 0 and a.prop = 0)
    join keys k2 on (k2.idkey = a.idcle)
  where k1.idkey <= L_ID_MAX
  and k2.idkey <= L_ID_MAX
  and exists (select 1 from objpro op where op.idobj = k1.idkey)
  and exists (select 1 from objpro op where op.idobj = k2.idkey)
  group by k1.objtyp,a.acctyplo,a.acctyphi,k2.objtyp;

  insert into DELTA_LINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select p_id,p_delta_type,o.CALLER_TYPE,o.LINK_TYPE_LO,o.LINK_TYPE_HI,o.CALLED_TYPE,o.VALUE,t1.objtypstr
    ,(select COALESCE(staticdesc,'xxx') from csv_linktype LT where LT.acctyplo = o.LINK_TYPE_LO and LT.acctyphi = o.LINK_TYPE_HI)
    ,t2.objtypstr,t1.lngstr
  from DELTA_WK_LINK o
    join objtypstr t1 on (t1.objtyp = o.CALLER_TYPE)
    join objtypstr t2 on (t2.objtyp = o.CALLED_TYPE);


  truncate table DELTA_WK_DYNLINK;
  -- TODO: compute the value for LINK_RF
  insert into DELTA_WK_DYNLINK (CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,LINK_STATUS,LINK_RF,VALUE)
  select k1.objtyp,a.acctyplo,a.acctyphi,k2.objtyp,case when a.prop = 1 then 'I' else 'E' end,'Y',count(1)
  from keys k1
    join acc a on (a.idclr = k1.idkey and a.accknd = 0 and a.prop > 0)
    join keys k2 on (k2.idkey = a.idcle)
  where k1.idkey <= L_ID_MAX
  and k2.idkey <= L_ID_MAX
  and exists (select 1 from objpro op where op.idobj = k1.idkey)
  and exists (select 1 from objpro op where op.idobj = k2.idkey)
  group by k1.objtyp,a.acctyplo,a.acctyphi,k2.objtyp,a.prop;

  insert into DELTA_DYNLINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,LINK_STATUS,LINK_RF,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select p_id,p_delta_type,o.CALLER_TYPE,o.LINK_TYPE_LO,o.LINK_TYPE_HI,o.CALLED_TYPE,o.LINK_STATUS,o.LINK_RF,o.VALUE,t1.objtypstr
    ,(select COALESCE(staticdesc,'xxx') from csv_linktype LT where LT.acctyplo = o.LINK_TYPE_LO and LT.acctyphi = o.LINK_TYPE_HI)
    ,t2.objtypstr,t1.lngstr
  from DELTA_WK_DYNLINK o
    join objtypstr t1 on (t1.objtyp = o.CALLER_TYPE)
    join objtypstr t2 on (t2.objtyp = o.CALLED_TYPE);

  return;
End;
$body$ 
LANGUAGE plpgsql;

create or replace FUNCTION delta_analyis_report_diff (p_id integer)
RETURNS void as
$body$
declare
L_ID_MAX integer := 0;
Begin
  delete from DELTA_OBJECT where ID = p_id and TYPE in ('X','N','D');

  insert into DELTA_OBJECT (ID,TYPE,OBJECT_TYPE,VALUE,OBJECT_TYPE_STR,LANGUAGE)
  select a.ID,'X',a.OBJECT_TYPE,(a.VALUE - b.VALUE),a.OBJECT_TYPE_STR,a.LANGUAGE
  from DELTA_OBJECT a
    join DELTA_OBJECT b on (b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and a.VALUE <> b.VALUE;

  insert into DELTA_OBJECT (ID,TYPE,OBJECT_TYPE,VALUE,OBJECT_TYPE_STR,LANGUAGE)
  select a.ID,'x',a.OBJECT_TYPE,(a.VALUE - b.VALUE),a.OBJECT_TYPE_STR,a.LANGUAGE
  from DELTA_OBJECT a
    join DELTA_OBJECT b on (b.ID = a.ID and b.TYPE = 'M' and b.OBJECT_TYPE = a.OBJECT_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and a.VALUE <> b.VALUE;
  
  insert into DELTA_OBJECT (ID,TYPE,OBJECT_TYPE,VALUE,OBJECT_TYPE_STR,LANGUAGE)
  select a.ID,'N',a.OBJECT_TYPE,a.VALUE,a.OBJECT_TYPE_STR,a.LANGUAGE
  from DELTA_OBJECT a
  where a.ID = p_id
  and a.TYPE = 'A'
  and not exists (select 1 from DELTA_OBJECT b where b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE);

  insert into DELTA_OBJECT (ID,TYPE,OBJECT_TYPE,VALUE,OBJECT_TYPE_STR,LANGUAGE)
  select a.ID,'n',a.OBJECT_TYPE,a.VALUE,a.OBJECT_TYPE_STR,a.LANGUAGE
  from DELTA_OBJECT a
  where a.ID = p_id
  and a.TYPE = 'M'
  and not exists (select 1 from DELTA_OBJECT b where b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE);

  insert into DELTA_OBJECT (ID,TYPE,OBJECT_TYPE,VALUE,OBJECT_TYPE_STR,LANGUAGE)
  select b.ID,'D',b.OBJECT_TYPE,b.VALUE * -1,b.OBJECT_TYPE_STR,b.LANGUAGE
  from DELTA_OBJECT b
  where b.ID = p_id
  and b.TYPE = 'B'
  and not exists (select 1 from DELTA_OBJECT a where a.ID = b.ID and a.TYPE = 'A' and a.OBJECT_TYPE = b.OBJECT_TYPE);



  delete from DELTA_PROPS where ID = p_id and TYPE in ('X','N','D');

  insert into DELTA_PROPS (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'X',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,(a.VALUE - b.VALUE),a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPS a
    join DELTA_PROPS b on (b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and a.VALUE <> b.VALUE;

  insert into DELTA_PROPS (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'x',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,(a.VALUE - b.VALUE),a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPS a
    join DELTA_PROPS b on (b.ID = a.ID and b.TYPE = 'M' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and a.VALUE <> b.VALUE;

  insert into DELTA_PROPS (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'N',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,a.VALUE,a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPS a
  where a.ID = p_id
  and a.TYPE = 'A'
  and not exists (select 1 from DELTA_PROPS b where b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE);

  insert into DELTA_PROPS (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'n',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,a.VALUE,a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPS a
  where a.ID = p_id
  and a.TYPE = 'M'
  and not exists (select 1 from DELTA_PROPS b where b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE);

  insert into DELTA_PROPS (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select b.ID,'D',b.OBJECT_TYPE,b.PROP_TYPE,b.PROP_SUB_TYPE,b.VALUE * -1,b.OBJECT_TYPE_STR,b.PROP_TYPE_STR,b.LANGUAGE
  from DELTA_PROPS b
  where b.ID = p_id
  and b.TYPE = 'B'
  and not exists (select 1 from DELTA_PROPS a where a.ID = b.ID and a.TYPE = 'A' and a.OBJECT_TYPE = b.OBJECT_TYPE and a.PROP_TYPE = b.PROP_TYPE and a.PROP_SUB_TYPE = b.PROP_SUB_TYPE);


  delete from DELTA_PROPN where ID = p_id and TYPE in ('X','N','D');

  insert into DELTA_PROPN (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'X',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,(a.VALUE - b.VALUE),(a.TOTAL - b.TOTAL),a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPN a
    join DELTA_PROPN b on (b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and (a.VALUE <> b.VALUE
  or a.TOTAL <> b.TOTAL);

  insert into DELTA_PROPN (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'x',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,(a.VALUE - b.VALUE),(a.TOTAL - b.TOTAL),a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPN a
    join DELTA_PROPN b on (b.ID = a.ID and b.TYPE = 'M' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and (a.VALUE <> b.VALUE
  or a.TOTAL <> b.TOTAL);

  insert into DELTA_PROPN (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'N',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,a.VALUE,a.TOTAL,a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPN a
  where a.ID = p_id
  and a.TYPE = 'A'
  and not exists (select 1 from DELTA_PROPN b where b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE);

  insert into DELTA_PROPN (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select a.ID,'n',a.OBJECT_TYPE,a.PROP_TYPE,a.PROP_SUB_TYPE,a.VALUE,a.TOTAL,a.OBJECT_TYPE_STR,a.PROP_TYPE_STR,a.LANGUAGE
  from DELTA_PROPN a
  where a.ID = p_id
  and a.TYPE = 'M'
  and not exists (select 1 from DELTA_PROPN b where b.ID = a.ID and b.TYPE = 'B' and b.OBJECT_TYPE = a.OBJECT_TYPE and b.PROP_TYPE = a.PROP_TYPE and b.PROP_SUB_TYPE = a.PROP_SUB_TYPE);

  insert into DELTA_PROPN (ID,TYPE,OBJECT_TYPE,PROP_TYPE,PROP_SUB_TYPE,VALUE,TOTAL,OBJECT_TYPE_STR,PROP_TYPE_STR,LANGUAGE)
  select b.ID,'D',b.OBJECT_TYPE,b.PROP_TYPE,b.PROP_SUB_TYPE,b.VALUE * -1,b.TOTAL * -1,b.OBJECT_TYPE_STR,b.PROP_TYPE_STR,b.LANGUAGE
  from DELTA_PROPN b
  where b.ID = p_id
  and b.TYPE = 'B'
  and not exists (select 1 from DELTA_PROPN a where a.ID = b.ID and a.TYPE = 'A' and a.OBJECT_TYPE = b.OBJECT_TYPE and a.PROP_TYPE = b.PROP_TYPE and a.PROP_SUB_TYPE = b.PROP_SUB_TYPE);


  delete from DELTA_LINK where ID = p_id and TYPE in ('X','N','D');

  insert into DELTA_LINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select a.ID,'X',a.CALLER_TYPE,a.LINK_TYPE_LO,a.LINK_TYPE_HI,a.CALLED_TYPE,(a.VALUE - b.VALUE),a.CALLER_TYPE_STR,a.LINK_TYPE_STR,a.CALLED_TYPE_STR,a.LANGUAGE
  from DELTA_LINK a
    join DELTA_LINK b on (b.ID = a.ID and b.TYPE = 'B' and b.CALLER_TYPE = a.CALLER_TYPE and b.LINK_TYPE_LO = a.LINK_TYPE_LO and b.LINK_TYPE_HI = a.LINK_TYPE_HI and b.CALLED_TYPE = a.CALLED_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and a.VALUE <> b.VALUE;

  insert into DELTA_LINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select a.ID,'x',a.CALLER_TYPE,a.LINK_TYPE_LO,a.LINK_TYPE_HI,a.CALLED_TYPE,(a.VALUE - b.VALUE),a.CALLER_TYPE_STR,a.LINK_TYPE_STR,a.CALLED_TYPE_STR,a.LANGUAGE
  from DELTA_LINK a
    join DELTA_LINK b on (b.ID = a.ID and b.TYPE = 'M' and b.CALLER_TYPE = a.CALLER_TYPE and b.LINK_TYPE_LO = a.LINK_TYPE_LO and b.LINK_TYPE_HI = a.LINK_TYPE_HI and b.CALLED_TYPE = a.CALLED_TYPE)
  where a.ID = p_id
  and a.TYPE = 'A'
  and a.VALUE <> b.VALUE;

  insert into DELTA_LINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select a.ID,'N',a.CALLER_TYPE,a.LINK_TYPE_LO,a.LINK_TYPE_HI,a.CALLED_TYPE,a.VALUE,a.CALLER_TYPE_STR,a.LINK_TYPE_STR,a.CALLED_TYPE_STR,a.LANGUAGE
  from DELTA_LINK a
  where a.ID = p_id
  and a.TYPE = 'A'
  and not exists (select 1 from DELTA_LINK b where b.ID = a.ID and b.TYPE = 'B' and b.CALLER_TYPE = a.CALLER_TYPE and b.LINK_TYPE_LO = a.LINK_TYPE_LO and b.LINK_TYPE_HI = a.LINK_TYPE_HI and b.CALLED_TYPE = a.CALLED_TYPE);

  insert into DELTA_LINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select a.ID,'n',a.CALLER_TYPE,a.LINK_TYPE_LO,a.LINK_TYPE_HI,a.CALLED_TYPE,a.VALUE,a.CALLER_TYPE_STR,a.LINK_TYPE_STR,a.CALLED_TYPE_STR,a.LANGUAGE
  from DELTA_LINK a
  where a.ID = p_id
  and a.TYPE = 'M'
  and not exists (select 1 from DELTA_LINK b where b.ID = a.ID and b.TYPE = 'B' and b.CALLER_TYPE = a.CALLER_TYPE and b.LINK_TYPE_LO = a.LINK_TYPE_LO and b.LINK_TYPE_HI = a.LINK_TYPE_HI and b.CALLED_TYPE = a.CALLED_TYPE);

  insert into DELTA_LINK (ID,TYPE,CALLER_TYPE,LINK_TYPE_LO,LINK_TYPE_HI,CALLED_TYPE,VALUE,CALLER_TYPE_STR,LINK_TYPE_STR,CALLED_TYPE_STR,LANGUAGE)
  select b.ID,'n',b.CALLER_TYPE,b.LINK_TYPE_LO,b.LINK_TYPE_HI,b.CALLED_TYPE,b.VALUE * -1,b.CALLER_TYPE_STR,b.LINK_TYPE_STR,b.CALLED_TYPE_STR,b.LANGUAGE
  from DELTA_LINK b
  where b.ID = p_id
  and b.TYPE = 'B'
  and not exists (select 1 from DELTA_LINK a where a.ID = b.ID and a.TYPE = 'B' and a.CALLER_TYPE = b.CALLER_TYPE and a.LINK_TYPE_LO = b.LINK_TYPE_LO and a.LINK_TYPE_HI = b.LINK_TYPE_HI and a.CALLED_TYPE = b.CALLED_TYPE);

  return;
End;
$body$ 
LANGUAGE plpgsql;
