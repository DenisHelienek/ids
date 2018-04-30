-- IDS, projekt 4
-- autori: Tomas Kazik xkazik03, Denis Helienek xhelie00

---------VYMAZANIE TABULIEK A SEKVENCII------------
DROP TABLE HOST CASCADE CONSTRAINTS;
DROP TABLE OBJEDNAVKA CASCADE CONSTRAINTS;
DROP TABLE REZERVACE CASCADE CONSTRAINTS;
DROP TABLE SLUZBA CASCADE CONSTRAINTS;
DROP TABLE VYKONANA_SLUZBA CASCADE CONSTRAINTS;
DROP TABLE POKOJ CASCADE CONSTRAINTS;

DROP SEQUENCE HOST_ID;
DROP SEQUENCE SLUZBA_ID;
DROP SEQUENCE VYKONANA_SLUZBA_ID;
DROP SEQUENCE POKOJ_ID;
DROP SEQUENCE REZERVACE_ID;
DROP SEQUENCE POCET_HOSTOV;
DROP SEQUENCE KONTROLA_MENA;
DROP SEQUENCE KONTROLA_CISLA;
DROP SEQUENCE KONTROLA_PRIEZVISKA;

drop materialized view zamestnanecPrijalCelkem;

-------VYTVORENIE TABULIEK---------------
CREATE TABLE HOST (
	id NUMBER NOT NULL,
	jmeno VARCHAR(20) NOT NULL,
	prijmeni VARCHAR(50) NOT NULL,
	datum_narozeni DATE NOT NULL,
	telefon NUMBER NOT NULL,
	email VARCHAR(50) NOT NULL,
	adresa VARCHAR(75) NOT NULL,
	CONSTRAINT host_id_primary PRIMARY KEY(id)
);

CREATE TABLE POKOJ (
	id NUMBER NOT NULL,
	kapacita NUMBER NOT NULL,
	cena_zakladni NUMBER NOT NULL,
	sezonni_priplatek NUMBER NOT NULL,
	sleva_pri_rezervaci NUMBER NOT NULL,
	popis VARCHAR(1000),
	CONSTRAINT pokoj_id_primary PRIMARY KEY(id)
);

CREATE TABLE SLUZBA (
	id NUMBER NOT NULL,
	nazev VARCHAR(50) NOT NULL,
	popis VARCHAR(200),
	cena NUMBER NOT NULL,
	CONSTRAINT sluzba_id_primary PRIMARY KEY (id)
);

CREATE TABLE OBJEDNAVKA (
	vs VARCHAR(10) NULL,
	vytvoreni_objednavky DATE NOT NULL,
	zaplaceno DATE,
	platbu_prijal VARCHAR(60), -- zde by bylo vhodne pouzit ciselnik, pro zjednoduseni jsme jej vsak nevyuzili
	konecna_cena NUMBER,
  	host_id NUMBER NOT NULL,
	CONSTRAINT FK_objednavka_host_id FOREIGN KEY(host_id) REFERENCES HOST(id),
	CONSTRAINT objednavka_id_primary PRIMARY KEY(vs)
);

CREATE TABLE REZERVACE (
	id NUMBER NOT NULL,
	objednavka_id VARCHAR(10) NOT NULL,
	pokoj_id NUMBER NOT NULL,
	rezervace_od DATE NOT NULL,
	rezervace_do DATE NOT NULL,
	nastoueni DATE,
	odhlaseni DATE,
	pocet_osob NUMBER NOT NULL,
	zruseno NUMBER NOT NULL,
	CONSTRAINT rezerzave_id_primary PRIMARY KEY (id),
	CONSTRAINT FK_rezervace_objednavka_id FOREIGN KEY(objednavka_id) REFERENCES OBJEDNAVKA(vs),
	CONSTRAINT FK_rezervace_pokoj_id FOREIGN KEY(pokoj_id) REFERENCES POKOJ(id)
);

CREATE TABLE VYKONANA_SLUZBA (
	id NUMBER NOT NULL,
	sluzba_id NUMBER NOT NULL,
	objednavka_id VARCHAR(10) NOT NULL,
	CONSTRAINT FK_vyksluzba_sluzba_id FOREIGN KEY(sluzba_id) REFERENCES SLUZBA(id),
	CONSTRAINT FK_vyksluzba_objednavka_id FOREIGN KEY(objednavka_id) REFERENCES OBJEDNAVKA(vs),
	CONSTRAINT vykonana_sluzba_id_primary PRIMARY KEY (id)
);

-------------TRIGGERY-----------
CREATE SEQUENCE HOST_ID INCREMENT BY 1 START WITH 1;
CREATE SEQUENCE REZERVACE_ID INCREMENT BY 1 START WITH 1;
CREATE SEQUENCE SLUZBA_ID INCREMENT BY 1 START WITH 1;
CREATE SEQUENCE VYKONANA_SLUZBA_ID INCREMENT BY 1 START WITH 1;
CREATE SEQUENCE POKOJ_ID INCREMENT BY 1 START WITH 1;
CREATE SEQUENCE POCET_HOSTOV;
CREATE SEQUENCE KONTROLA_MENA;
CREATE SEQUENCE KONTROLA_CISLA;
CREATE SEQUENCE KONTROLA_PRIEZVISKA;

CREATE OR REPLACE TRIGGER vs_trigger
	BEFORE INSERT ON OBJEDNAVKA
	FOR EACH ROW
BEGIN
	:NEW.vs := TO_CHAR(:NEW.vytvoreni_objednavky,'yymmddHH24MI');
END;
/

CREATE OR REPLACE TRIGGER konecna_cena_trigger
	AFTER INSERT OR DELETE ON VYKONANA_SLUZBA
	FOR EACH ROW
BEGIN
  CASE
    WHEN INSERTING THEN
		konecna_cena_insert(:NEW.sluzba_id,:NEW.objednavka_id);
    WHEN DELETING THEN
		konecna_cena_delete(:OLD.sluzba_id,:OLD.objednavka_id);
  END CASE;
END;
/

CREATE OR REPLACE TRIGGER pocet_hostov_trigger
    BEFORE INSERT ON HOST
    FOR EACH ROW
BEGIN
    :NEW.id := POCET_HOSTOV.NEXTVAL;
END POCET_HOSTOV;
/

CREATE OR REPLACE TRIGGER kontrola_mena_trigger
    BEFORE INSERT OR UPDATE OF jmeno ON HOST
    FOR EACH ROW
DECLARE
    j HOST.jmeno%TYPE;
BEGIN
    j := :NEW.jmeno;
    IF (LENGTH(j) < 1) THEN
        Raise_Application_Error (-9999, 'Prilis kratke meno');
    END IF;
END KONTROLA_MENA;
/

CREATE OR REPLACE TRIGGER kontrola_priezviska_trigger
    BEFORE INSERT OR UPDATE OF prijmeni ON HOST
    FOR EACH ROW
DECLARE
    p HOST.prijmeni%TYPE;
BEGIN
    p := :NEW.prijmeni;
    IF (LENGTH(p) < 1) THEN
        Raise_Application_Error (-9998, 'Prilis kratke priezvisko');
    END IF;
END KONTROLA_PRIEZVISKA;
/

CREATE OR REPLACE TRIGGER kontrola_cisla_trigger
    BEFORE INSERT OR UPDATE OF telefon ON HOST
    FOR EACH ROW
DECLARE
    predvolba NUMBER;
    t HOST.telefon%TYPE;
BEGIN
    t := :NEW.telefon;
    predvolba := SUBSTR(t, 1, 3);
    IF (predvolba != 421) THEN
        Raise_Application_Error (-9997, 'Zla predvolba');
    END IF;
END KONTROLA_CISLA;
/

-------------PROCEDURY----------------

SET serveroutput ON;

create or replace procedure poc_rez_pok_percentualne(idPokoj IN NUMBER)
is
	cursor curs is select * from REZERVACE;
	hledanyPokoj number;
	vsechnyPokoje number;
	begin
		hledanyPokoj := 0;
		vsechnyPokoje := 0;
		for row in curs loop
			if (row.pokoj_id = idPokoj) then
				hledanyPokoj := hledanyPokoj + 1;
			end if;
			vsechnyPokoje := vsechnyPokoje + 1;
		end loop;
		dbms_output.put_line('Dany pokoj vlastni '||ROUND(hledanyPokoj / vsechnyPokoje * 100, 2)||'% vsech rezervaci.');
	end;
/

CREATE OR REPLACE PROCEDURE klientCelkoveZaplatil(idKlient IN NUMBER)
is
	cursor curs is select host_id, konecna_cena from OBJEDNAVKA;
	celkemZaplaceno objednavka.konecna_cena%TYPE;
	begin
		celkemZaplaceno := 0;
		for row in curs loop
			if (row.host_id = idKlient) then
				celkemZaplaceno := celkemZaplaceno + row.konecna_cena;
			end if;
		end loop;
		dbms_output.put_line(idKlient || ' utratil celkem ' || celkemZaplaceno);
		exception
			when others then
				raise_application_error(-20010, 'Neocekavana chyba');
	end;
/

CREATE OR REPLACE PROCEDURE konecna_cena_delete (sluzbaID NUMBER, objVS VARCHAR) AS
SCena SLUZBA.cena%TYPE;
KCena OBJEDNAVKA.konecna_cena%TYPE;
BEGIN
  SELECT cena INTO SCena FROM SLUZBA WHERE id = sluzbaID;
  SELECT konecna_cena INTO KCena FROM OBJEDNAVKA WHERE vs = objVS;
  UPDATE OBJEDNAVKA SET konecna_cena = KCena - SCena WHERE vs = objVS;
END;
/

CREATE OR REPLACE PROCEDURE konecna_cena_insert (sluzbaID NUMBER, objVS VARCHAR) AS
SCena SLUZBA.cena%TYPE;
KCena OBJEDNAVKA.konecna_cena%TYPE;
BEGIN
  SELECT cena INTO SCena FROM SLUZBA WHERE id = sluzbaID;
  SELECT konecna_cena INTO KCena FROM OBJEDNAVKA WHERE vs = objVS;
  UPDATE OBJEDNAVKA SET konecna_cena = KCena + SCena WHERE vs = objVS;
END;
/

-------INSERTY-----------
INSERT INTO SLUZBA VALUES(SLUZBA_ID.NEXTVAL, 'Uklid navic', '', 650);
INSERT INTO SLUZBA VALUES(SLUZBA_ID.NEXTVAL, 'Donaska zmrzliny', 'Donaska 2 porci zmrzliny v dezertnich miskach dle aktualni nabidky', 150);
INSERT INTO SLUZBA VALUES(SLUZBA_ID.NEXTVAL, 'Vymena rucniku navic', '', 50);
INSERT INTO SLUZBA VALUES(SLUZBA_ID.NEXTVAL, 'Snidane v restauracnim salonku', 'Snidane pro 2 osoby', 700);

INSERT INTO POKOJ VALUES(POKOJ_ID.NEXTVAL, 2, 1200, 200, 50, 'Manzelska postel, sprcha, televize, klimatizace' );
INSERT INTO POKOJ VALUES(POKOJ_ID.NEXTVAL, 2, 1200, 200, 50, 'Manzelska postel, sprcha, televize, klimatizace' );
INSERT INTO POKOJ VALUES(POKOJ_ID.NEXTVAL, 3, 1500, 250, 75, 'Manzelska postel, pristylka, vana, televize, klimatizace' );
INSERT INTO POKOJ VALUES(POKOJ_ID.NEXTVAL, 5, 5000, 850, 235, 'Apartma, manzelska postel, 3 oddelene, vana, sprcha, kuchyne, televize, klimatizace' );

INSERT INTO HOST VALUES( HOST_ID.NEXTVAL, 'Pavel', 'Koutný', TO_DATE('30-03-1987', 'dd-mm-yyyy'), 421758340, 'pavel@koutny.cz', 'Kozí 29 Ostrava 47869');
INSERT INTO HOST VALUES( HOST_ID.NEXTVAL, 'Petr', 'Filip', TO_DATE('05-03-1987', 'dd-mm-yyyy'), 421284130, 'filip@ovci.cz','Ovčí 104 Brno 60200');
INSERT INTO HOST VALUES( HOST_ID.NEXTVAL, 'Oldřich', 'Bejr', TO_DATE('30-03-1967', 'dd-mm-yyyy'), 421012845, 'oldrich@seznam.cz', 'Havraní 90 Jakubov 39475');
INSERT INTO HOST VALUES( HOST_ID.NEXTVAL, 'Kristýna', 'Kocarova', TO_DATE('08-01-1987', 'dd-mm-yyyy'), 421048723, 'vgfddf@centrum.cz', 'Václavské náměstí 48 Rosice 29481');
INSERT INTO HOST VALUES( HOST_ID.NEXTVAL, 'Olga', 'Vráblová', TO_DATE('30-03-1954', 'dd-mm-yyyy'), 421365971, 'vrablova@seznam.cz', 'Masarykova 394 Náměšť nad Oslavou 84723');

INSERT INTO OBJEDNAVKA VALUES('', TO_DATE('05-03-2017 13:09', 'dd-mm-yyyy HH24:MI'), TO_DATE('06-03-2017 10:15', 'dd-mm-yyyy HH24:MI'), 'Standa', 0, 3);
INSERT INTO OBJEDNAVKA VALUES('', TO_DATE('05-03-2017 10:12', 'dd-mm-yyyy HH24:MI'), NULL, NULL, NULL, 1);
INSERT INTO OBJEDNAVKA VALUES('', TO_DATE('26-02-2017 06:17', 'dd-mm-yyyy HH24:MI'), TO_DATE('03-03-2017 09:49', 'dd-mm-yyyy HH24:MI'), 'Kamila', 0, 5);
INSERT INTO OBJEDNAVKA VALUES('', TO_DATE('24-02-2017 21:58', 'dd-mm-yyyy HH24:MI'), NULL, NULL, NULL, 2);
INSERT INTO OBJEDNAVKA VALUES('', TO_DATE('02-03-2017 17:01', 'dd-mm-yyyy HH24:MI'), TO_DATE('04-03-2017 07:23', 'dd-mm-yyyy HH24:MI'), 'Kamila', 0, 4);

INSERT INTO REZERVACE VALUES(REZERVACE_ID.NEXTVAL, '1703051309', 3, TO_DATE('05-03-2017', 'dd-mm-yyyy'), TO_DATE('06-03-2017', 'dd-mm-yyyy'), TO_DATE('05-03-2017 13:09', 'dd-mm-yyyy HH24:MI'), TO_DATE('06-03-2017 10:14', 'dd-mm-yyyy HH24:MI'), 2, 0 );
INSERT INTO REZERVACE VALUES(REZERVACE_ID.NEXTVAL, '1703051012', 3, TO_DATE('06-04-2017', 'dd-mm-yyyy'), TO_DATE('08-04-2017', 'dd-mm-yyyy'), NULL, NULL, 2, 0 );
INSERT INTO REZERVACE VALUES(REZERVACE_ID.NEXTVAL, '1702260617', 2, TO_DATE('28-02-2017', 'dd-mm-yyyy'), TO_DATE('03-03-2017', 'dd-mm-yyyy'), TO_DATE('28-03-2017 14:08', 'dd-mm-yyyy HH24:MI'), TO_DATE('03-03-2017 09:47', 'dd-mm-yyyy HH24:MI'), 3, 0 );
INSERT INTO REZERVACE VALUES(REZERVACE_ID.NEXTVAL, '1702242158', 2, TO_DATE('01-03-2017', 'dd-mm-yyyy'), TO_DATE('02-03-2017', 'dd-mm-yyyy'), NULL, NULL, 2, 1 );
INSERT INTO REZERVACE VALUES(REZERVACE_ID.NEXTVAL, '1703021701', 4, TO_DATE('02-03-2017', 'dd-mm-yyyy'), TO_DATE('04-03-2014', 'dd-mm-yyyy'), TO_DATE('02-03-2017 21:34', 'dd-mm-yyyy HH24:MI'), TO_DATE('04-03-2017 07:20', 'dd-mm-yyyy HH24:MI'), 1, 0 );


INSERT INTO VYKONANA_SLUZBA VALUES(VYKONANA_SLUZBA_ID.NEXTVAL, 1, '1702260617');
INSERT INTO VYKONANA_SLUZBA VALUES(VYKONANA_SLUZBA_ID.NEXTVAL, 1, '1702260617');
INSERT INTO VYKONANA_SLUZBA VALUES(VYKONANA_SLUZBA_ID.NEXTVAL, 2, '1702260617');
INSERT INTO VYKONANA_SLUZBA VALUES(VYKONANA_SLUZBA_ID.NEXTVAL, 1, '1702260617');
INSERT INTO VYKONANA_SLUZBA VALUES(VYKONANA_SLUZBA_ID.NEXTVAL, 3, '1703021701');

---------SELECTY-----------

-- predvedeni seznamu objednavek - jsou vyplneny variabilni symboly a zaroven i secteny ceny za sluzby v "konecna_cena"
-- konecna cena neobsahuje poplatek za pobyt, ktery by byl dopocitan pri placeni pobytu
--SELECT * FROM OBJEDNAVKA;

-- predvedeni odstraneni vykonane sluzby - konecna cena u objenavky se aktualizuje
DELETE FROM VYKONANA_SLUZBA WHERE id = 2;
--SELECT * FROM OBJEDNAVKA;
--SELECT * FROM VYKONANA_SLUZBA;

--SELECT * FROM OBJEDNAVKA LEFT JOIN HOST ON OBJEDNAVKA.host_id = HOST.id WHERE OBJEDNAVKA.zaplaceno IS NULL;
--vráti hosťov a objednávku, ktorý ešte nezaplatili objednávku

--SELECT REZERVACE.rezervace_od, REZERVACE.rezervace_do, REZERVACE.nastoueni, REZERVACE.odhlaseni, REZERVACE.pocet_osob, POKOJ.kapacita, POKOJ.popis FROM REZERVACE INNER JOIN POKOJ ON REZERVACE.pokoj_id = POKOJ.id;
--vrati info ku rezervacii, aky typ izba, kolko osob atd

--SELECT * FROM VYKONANA_SLUZBA LEFT JOIN SLUZBA ON VYKONANA_SLUZBA.sluzba_id = SLUZBA.id LEFT JOIN OBJEDNAVKA ON VYKONANA_SLUZBA.objednavka_id = OBJEDNAVKA.vs;
--vráti ku objednávke vykonané služby

--SELECT AVG(pocet_osob) as priemerny_pocet_osob FROM REZERVACE GROUP BY pokoj_id;
--vrati priemerny pocet osob pre izby

--SELECT sluzba_id, COUNT(objednavka_id) as pocet_objednani FROM VYKONANA_SLUZBA GROUP BY sluzba_id;
--pocet objednani danej sluzby

--SELECT * FROM REZERVACE WHERE EXISTS (SELECT * FROM POKOJ WHERE REZERVACE.pokoj_id = POKOJ.id);
-- test na neprazdnost tabulky s korelovanym poddotazom, vypise rezervacky

--SELECT * FROM OBJEDNAVKA WHERE vs IN (SELECT objednavka_id FROM VYKONANA_SLUZBA);
--objednávky, ktoré si objednali doplnkove služby

------PRAVA-------

GRANT EXECUTE ON konecna_cena_insert TO XHELIE00;
GRANT EXECUTE ON konecna_cena_delete TO XHELIE00;
GRANT ALL ON HOST TO XHELIE00;
GRANT ALL ON POKOJ TO XHELIE00;
GRANT ALL ON SLUZBA TO XHELIE00;
GRANT ALL ON OBJEDNAVKA TO XHELIE00;
GRANT ALL ON REZERVACE TO XHELIE00;
GRANT ALL ON VYKONANA_SLUZBA TO XHELIE00;

GRANT EXECUTE ON konecna_cena_insert TO XKAZIK03;
GRANT EXECUTE ON konecna_cena_delete TO XKAZIK03;
GRANT ALL ON HOST TO XKAZIK03;
GRANT ALL ON POKOJ TO XKAZIK03;
GRANT ALL ON SLUZBA TO XKAZIK03;
GRANT ALL ON OBJEDNAVKA TO XKAZIK03;
GRANT ALL ON REZERVACE TO XKAZIK03;
GRANT ALL ON VYKONANA_SLUZBA TO XKAZIK03;

-------EXPLAIN-------
EXPLAIN PLAN FOR
SELECT prijmeni, SUM(konecna_cena)
FROM HOST NATURAL JOIN OBJEDNAVKA
GROUP BY prijmeni;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

CREATE INDEX i ON HOST(prijmeni);
EXPLAIN PLAN FOR
SELECT /*+ INDEX HOST i)*/prijmeni, SUM(konecna_cena)
FROM HOST NATURAL JOIN OBJEDNAVKA
GROUP BY prijmeni;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-------POHLED-------
create materialized view log on OBJEDNAVKA with primary key,rowid (platbu_prijal, konecna_cena) including new values;
create materialized view zamestnanecPrijalCelkem
	cache
	build immediate
	refresh fast on commit
	enable query rewrite
	as
		select obj.platbu_prijal, sum(obj.konecna_cena) as PrijalCelkem
		from OBJEDNAVKA obj
		group by obj.platbu_prijal;

grant all on zamestnanecPrijalCelkem to XHELIE00;
grant all on zamestnanecPrijalCelkem to XKAZIK03;

BEGIN
	POC_REZ_POK_PERCENTUALNE(2);
END;

begin
	klientCelkoveZaplatil(5);
end;

select * from zamestnanecPrijalCelkem;