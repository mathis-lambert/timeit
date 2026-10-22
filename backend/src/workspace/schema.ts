import { Type, type Static } from '@sinclair/typebox';

const id = Type.String({ format: 'uuid' });
const text = Type.String({ maxLength: 500 });
const date = Type.String({ format: 'date-time' });
const currency = Type.String({ pattern: '^[A-Z]{3}$' });
const decimal = Type.String({ pattern: '^\\d{1,10}(\\.\\d{1,8})?$' });
const percent = Type.String({ pattern: '^(100(\\.0+)?|[0-9]{1,2}(\\.[0-9]{1,4})?)$' });
const color = Type.String({ enum: ['coral', 'blue', 'green', 'purple', 'gold'] });
const object = <T extends Parameters<typeof Type.Object>[0]>(properties: T) => Type.Object(properties, { additionalProperties: false });

export const WorkspaceSchema = object({
  schemaVersion: Type.Literal(1),
  profile: object({ name: text, currency, weeklyGoal: Type.Integer({ minimum: 1, maximum: 168 }), timezone: Type.String({ minLength: 1, maxLength: 100 }) }),
  clients: Type.Array(object({ id, name: Type.String({ minLength: 1, maxLength: 150 }), color }), { maxItems: 1000 }),
  projects: Type.Array(object({ id, clientID: id, name: Type.String({ minLength: 1, maxLength: 150 }), color, currency, hourlyRate: decimal, billable: Type.Boolean(), archived: Type.Boolean() }), { maxItems: 3000 }),
  taxPolicies: Type.Array(object({ id, effectiveFrom: date, contributions: percent, incomeTax: percent }), { minItems: 1, maxItems: 1000 }),
  entries: Type.Array(object({
    id, projectID: id, title: text, start: date, end: Type.Union([date, Type.Null()]),
    currency, hourlyRate: decimal, billable: Type.Boolean(), contributions: percent, incomeTax: percent,
  }), { maxItems: 20000 }),
});

export const SyncSchema = object({
  baseRevision: Type.Integer({ minimum: 0 }),
  mutationID: id,
  document: WorkspaceSchema,
});
export type Workspace = Static<typeof WorkspaceSchema>;
export type SyncRequest = Static<typeof SyncSchema>;

export function validateWorkspace(document: Workspace): string | undefined {
  try { new Intl.DateTimeFormat('en', { timeZone: document.profile.timezone }); } catch { return 'Unknown timezone.'; }
  for (const values of [document.clients, document.projects, document.entries, document.taxPolicies]) {
    if (new Set(values.map(item => item.id)).size !== values.length) return 'Duplicate identifiers.';
  }
  const clients = new Set(document.clients.map(item => item.id));
  const projects = new Set(document.projects.map(item => item.id));
  if (document.projects.some(project => !clients.has(project.clientID))) return 'A project references an unknown client.';
  if (document.entries.some(entry => !projects.has(entry.projectID))) return 'An entry references an unknown project.';
  if (document.entries.filter(entry => entry.end === null).length > 1) return 'Only one running timer is allowed.';
  if (document.entries.some(entry => entry.end !== null && new Date(entry.end) <= new Date(entry.start))) return 'An entry must end after it starts.';
  if (document.entries.some(entry => new Date(entry.start).getTime() > Date.now() + 60_000)) return 'A timer cannot start in the future.';
  if (document.entries.some(entry => entry.end !== null && new Date(entry.end).getTime() > Date.now() + 60_000)) return 'An entry cannot end in the future.';
  if (document.taxPolicies.some(policy => Number(policy.contributions) + Number(policy.incomeTax) > 100)) return 'Combined deductions cannot exceed 100%.';
  if (document.entries.some(entry => Number(entry.contributions) + Number(entry.incomeTax) > 100)) return 'Combined deductions cannot exceed 100%.';
}
