BEGIN;

-- Core relational model required by the clinic specification.
-- The legacy JSON state remains available during the migration period;
-- these tables are the source-of-truth foundation for the next API phase.

CREATE TABLE IF NOT EXISTS clinics (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name TEXT NOT NULL,
  logo_url TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS services (
  id UUID PRIMARY KEY,
  clinic_id UUID REFERENCES clinics(id),
  branch_id UUID REFERENCES branches(id),
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  duration_minutes INTEGER NOT NULL DEFAULT 15,
  daily_limit INTEGER,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patients (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE,
  file_number TEXT UNIQUE,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  date_of_birth DATE,
  gender TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  emergency_contact JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS doctors (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE,
  clinic_id UUID REFERENCES clinics(id),
  specialty TEXT NOT NULL DEFAULT '',
  license_number TEXT NOT NULL DEFAULT '',
  bio TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS receptionists (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE,
  clinic_id UUID REFERENCES clinics(id),
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS clinic_managers (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE,
  clinic_id UUID REFERENCES clinics(id),
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS admins (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS doctor_services (
  doctor_id TEXT NOT NULL,
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  price NUMERIC(12,2),
  duration_minutes INTEGER,
  PRIMARY KEY (doctor_id, service_id)
);

CREATE TABLE IF NOT EXISTS doctor_schedules (
  id UUID PRIMARY KEY,
  doctor_id TEXT NOT NULL,
  branch_id UUID REFERENCES branches(id),
  weekday SMALLINT NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  slot_duration_minutes INTEGER NOT NULL DEFAULT 15,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS appointments (
  id UUID PRIMARY KEY,
  clinic_id UUID REFERENCES clinics(id),
  branch_id UUID REFERENCES branches(id),
  patient_id TEXT NOT NULL,
  doctor_id TEXT NOT NULL,
  service_id UUID REFERENCES services(id),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'booked' CHECK (status IN ('booked','confirmed','checked_in','in_consultation','completed','cancelled','no_show')),
  source TEXT NOT NULL DEFAULT 'staff',
  notes TEXT NOT NULL DEFAULT '',
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS visits (
  id UUID PRIMARY KEY,
  appointment_id UUID UNIQUE REFERENCES appointments(id),
  patient_id TEXT NOT NULL,
  doctor_id TEXT NOT NULL,
  branch_id UUID REFERENCES branches(id),
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','completed','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS medical_records (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  visit_id UUID REFERENCES visits(id),
  doctor_id TEXT,
  record_type TEXT NOT NULL DEFAULT 'note',
  content TEXT NOT NULL DEFAULT '',
  visibility TEXT NOT NULL DEFAULT 'care_team' CHECK (visibility IN ('patient','care_team','private')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS diagnoses (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  visit_id UUID REFERENCES visits(id),
  doctor_id TEXT,
  code TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notes (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  visit_id UUID REFERENCES visits(id),
  author_id TEXT NOT NULL,
  body TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'care_team',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS medications (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  generic_name TEXT NOT NULL DEFAULT '',
  trade_name TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  dose TEXT NOT NULL DEFAULT '',
  usage_instructions TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS prescriptions (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  doctor_id TEXT NOT NULL,
  visit_id UUID REFERENCES visits(id),
  status TEXT NOT NULL DEFAULT 'issued' CHECK (status IN ('draft','issued','dispensing','dispensed','cancelled')),
  instructions TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS prescription_items (
  id UUID PRIMARY KEY,
  prescription_id UUID NOT NULL REFERENCES prescriptions(id) ON DELETE CASCADE,
  medication_id UUID REFERENCES medications(id),
  medication_name TEXT NOT NULL DEFAULT '',
  dose TEXT NOT NULL DEFAULT '',
  frequency TEXT NOT NULL DEFAULT '',
  duration TEXT NOT NULL DEFAULT '',
  instructions TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS assessments (
  id UUID PRIMARY KEY,
  clinic_id UUID REFERENCES clinics(id),
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS assessment_questions (
  id UUID PRIMARY KEY,
  assessment_id UUID NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
  question_text TEXT NOT NULL,
  question_type TEXT NOT NULL DEFAULT 'text',
  options JSONB NOT NULL DEFAULT '[]'::jsonb,
  sort_order INTEGER NOT NULL DEFAULT 0,
  required BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS assessment_assignments (
  id UUID PRIMARY KEY,
  assessment_id UUID NOT NULL REFERENCES assessments(id),
  patient_id TEXT NOT NULL,
  doctor_id TEXT,
  visit_id UUID REFERENCES visits(id),
  status TEXT NOT NULL DEFAULT 'assigned',
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS assessment_answers (
  id UUID PRIMARY KEY,
  assignment_id UUID NOT NULL REFERENCES assessment_assignments(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES assessment_questions(id),
  answer JSONB NOT NULL DEFAULT 'null'::jsonb
);

CREATE TABLE IF NOT EXISTS assessment_results (
  id UUID PRIMARY KEY,
  assignment_id UUID NOT NULL REFERENCES assessment_assignments(id) ON DELETE CASCADE,
  score NUMERIC(12,2),
  interpretation TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The existing lab_orders/lab_results and radiology_orders tables are created by
-- migration 002; these indexes align them with patient/branch queries.
CREATE INDEX IF NOT EXISTS appointments_patient_time_idx ON appointments(patient_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS appointments_doctor_time_idx ON appointments(doctor_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS patients_search_idx ON patients(phone, email, file_number);
CREATE INDEX IF NOT EXISTS medical_records_patient_time_idx ON medical_records(patient_id, created_at DESC);

CREATE TABLE IF NOT EXISTS follow_ups (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  doctor_id TEXT,
  visit_id UUID REFERENCES visits(id),
  due_at TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','cancelled')),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoices (
  id UUID PRIMARY KEY,
  clinic_id UUID REFERENCES clinics(id),
  branch_id UUID REFERENCES branches(id),
  patient_id TEXT NOT NULL,
  appointment_id UUID REFERENCES appointments(id),
  total NUMERIC(12,2) NOT NULL DEFAULT 0,
  paid NUMERIC(12,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid','partial','paid','refunded')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY,
  invoice_id UUID REFERENCES invoices(id),
  patient_id TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  method TEXT NOT NULL DEFAULT 'cash',
  status TEXT NOT NULL DEFAULT 'paid' CHECK (status IN ('paid','refunded','void')),
  received_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  assigned_to TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL,
  body TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS files (
  id UUID PRIMARY KEY,
  patient_id TEXT NOT NULL,
  visit_id UUID REFERENCES visits(id),
  uploaded_by TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  file_name TEXT NOT NULL,
  mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
  visibility TEXT NOT NULL DEFAULT 'care_team',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS counter_requests (
  id UUID PRIMARY KEY,
  branch_id UUID REFERENCES branches(id),
  patient_id TEXT,
  appointment_id UUID REFERENCES appointments(id),
  request_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'waiting',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY,
  actor_id TEXT,
  actor_role TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL DEFAULT '',
  entity_id TEXT NOT NULL DEFAULT '',
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;
