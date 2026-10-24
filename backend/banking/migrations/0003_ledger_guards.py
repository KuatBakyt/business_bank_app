from django.db import migrations

SQL = r'''
CREATE FUNCTION bank_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'immutable financial or audit record' USING ERRCODE='23514';
END; $$;
CREATE TRIGGER immutable_journal BEFORE UPDATE OR DELETE ON banking_journaltransaction
FOR EACH ROW EXECUTE FUNCTION bank_immutable();
CREATE TRIGGER immutable_entry BEFORE UPDATE OR DELETE ON banking_ledgerentry
FOR EACH ROW EXECUTE FUNCTION bank_immutable();
CREATE TRIGGER immutable_audit BEFORE UPDATE OR DELETE ON banking_auditevent
FOR EACH ROW EXECUTE FUNCTION bank_immutable();

CREATE FUNCTION bank_entry_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE born text;
BEGIN
  SELECT xmin::text INTO born FROM banking_journaltransaction WHERE id=NEW.journal_id;
  IF born IS DISTINCT FROM (pg_current_xact_id()::text) THEN
    RAISE EXCEPTION 'cannot append to committed journal' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER entries_same_transaction BEFORE INSERT ON banking_ledgerentry
FOR EACH ROW EXECUTE FUNCTION bank_entry_insert();

CREATE FUNCTION bank_check_journal() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE jid uuid; n bigint; total numeric; j banking_journaltransaction; p banking_payment;
BEGIN
  IF TG_TABLE_NAME='banking_ledgerentry' THEN jid := NEW.journal_id; ELSE jid := NEW.id; END IF;
  SELECT * INTO j FROM banking_journaltransaction WHERE id=jid;
  SELECT count(*), COALESCE(sum(CASE WHEN side='DEBIT' THEN amount ELSE -amount END),0)
    INTO n,total FROM banking_ledgerentry WHERE journal_id=jid;
  IF n <> 2 OR total <> 0 THEN
    RAISE EXCEPTION 'journal must have two balanced entries' USING ERRCODE='23514';
  END IF;
  IF j.kind='TRANSFER' THEN
    SELECT * INTO p FROM banking_payment WHERE id=j.payment_id;
    IF p.status <> 'EXECUTED' OR
       NOT EXISTS (SELECT 1 FROM banking_ledgerentry WHERE journal_id=jid AND account_id=p.source_id AND side='DEBIT' AND amount=p.amount) OR
       NOT EXISTS (SELECT 1 FROM banking_ledgerentry WHERE journal_id=jid AND account_id=p.destination_id AND side='CREDIT' AND amount=p.amount) THEN
      RAISE EXCEPTION 'payment and journal mismatch' USING ERRCODE='23514';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM banking_ledgerentry e JOIN banking_account a ON a.id=e.account_id WHERE e.journal_id=jid AND e.side='DEBIT' AND a.is_system)
       OR NOT EXISTS (SELECT 1 FROM banking_ledgerentry e JOIN banking_account a ON a.id=e.account_id WHERE e.journal_id=jid AND e.side='CREDIT' AND NOT a.is_system) THEN
      RAISE EXCEPTION 'invalid demo funding entries' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER journal_balanced AFTER INSERT ON banking_journaltransaction
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bank_check_journal();
CREATE CONSTRAINT TRIGGER entries_balanced AFTER INSERT ON banking_ledgerentry
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bank_check_journal();

CREATE FUNCTION bank_check_balance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE aid uuid; a banking_account; expected numeric;
BEGIN
  IF TG_TABLE_NAME='banking_ledgerentry' THEN aid := NEW.account_id; ELSE aid := NEW.id; END IF;
  SELECT * INTO a FROM banking_account WHERE id=aid FOR UPDATE;
  SELECT COALESCE(sum(CASE WHEN side='CREDIT' THEN amount ELSE -amount END),0)
    INTO expected FROM banking_ledgerentry WHERE account_id=aid;
  IF a.is_system THEN expected := -expected; END IF;
  IF expected <> a.cached_balance OR expected < 0 THEN
    RAISE EXCEPTION 'cached balance does not match ledger' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER account_balance AFTER INSERT OR UPDATE ON banking_account
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bank_check_balance();
CREATE CONSTRAINT TRIGGER entry_balance AFTER INSERT ON banking_ledgerentry
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bank_check_balance();

CREATE FUNCTION bank_guard_payment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.status IN ('EXECUTED','REJECTED','CANCELLED') THEN
    RAISE EXCEPTION 'terminal payment is immutable' USING ERRCODE='23514';
  END IF;
  IF OLD.status='PENDING_APPROVAL' AND
     (NEW.source_id,NEW.destination_id,NEW.amount,NEW.purpose,NEW.author_id) IS DISTINCT FROM
     (OLD.source_id,OLD.destination_id,OLD.amount,OLD.purpose,OLD.author_id) THEN
    RAISE EXCEPTION 'submitted payment details are immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER payment_immutable BEFORE UPDATE OR DELETE ON banking_payment
FOR EACH ROW EXECUTE FUNCTION bank_guard_payment();
CREATE FUNCTION bank_check_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p banking_payment; n bigint;
BEGIN
  SELECT * INTO p FROM banking_payment WHERE id=NEW.id;
  SELECT count(*) INTO n FROM banking_journaltransaction WHERE payment_id=p.id;
  IF p.status='EXECUTED' AND (n<>1 OR p.executed_at IS NULL OR p.approver_id IS NULL) THEN
    RAISE EXCEPTION 'executed payment needs journal and approver' USING ERRCODE='23514';
  END IF;
  IF p.status<>'EXECUTED' AND n<>0 THEN
    RAISE EXCEPTION 'unexecuted payment cannot have journal' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER executed_payment AFTER INSERT OR UPDATE ON banking_payment
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bank_check_payment();
'''

REVERSE = '''
DROP TRIGGER executed_payment ON banking_payment;
DROP TRIGGER payment_immutable ON banking_payment;
DROP TRIGGER entry_balance ON banking_ledgerentry;
DROP TRIGGER account_balance ON banking_account;
DROP TRIGGER entries_balanced ON banking_ledgerentry;
DROP TRIGGER journal_balanced ON banking_journaltransaction;
DROP TRIGGER entries_same_transaction ON banking_ledgerentry;
DROP TRIGGER immutable_journal ON banking_journaltransaction;
DROP TRIGGER immutable_entry ON banking_ledgerentry;
DROP TRIGGER immutable_audit ON banking_auditevent;
DROP FUNCTION bank_check_payment(),bank_guard_payment(),bank_check_balance(),bank_check_journal(),bank_entry_insert(),bank_immutable();
'''
class Migration(migrations.Migration):
    dependencies = [('banking', '0002_initial')]
    operations = [migrations.RunSQL(SQL, REVERSE)]
