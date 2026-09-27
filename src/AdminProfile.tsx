import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from 'react'
import {
  Button,
  Cell,
  List,
  Placeholder,
  Section,
  Spinner,
  TabsList,
} from '@telegram-apps/telegram-ui'
import SheetCloseButton from './components/SheetCloseButton'
import TelegramFormField from './components/TelegramFormField'
import TelegramInput from './components/TelegramInput'
import TelegramSelect from './components/TelegramSelect'
import TelegramSwitch from './components/TelegramSwitch'
import TelegramTextarea from './components/TelegramTextarea'
import {
  isoToLocalInput,
  loadAdminCatalog,
  saveAdminDancer,
  saveAdminEvent,
  saveAdminGroup,
  saveAdminLevel,
  saveAdminStyle,
  saveAdminVenue,
  type AdminCatalog,
  type AdminCompetitionProfile,
  type AdminDancer,
  type AdminDancerStyleProfile,
  type AdminEvent,
  type AdminGroup,
  type AdminLevel,
  type AdminStyle,
  type AdminVenue,
} from './lib/admin'

export type AdminView = 'dancers' | 'schedule' | 'settings'

type LoadState =
  | { status: 'loading'; data: null; error: null }
  | { status: 'ready'; data: AdminCatalog; error: null }
  | { status: 'error'; data: null; error: string }

type EditorState =
  | { type: 'dancer'; item: AdminDancer | null }
  | { type: 'group'; item: AdminGroup | null }
  | { type: 'event'; item: AdminEvent | null }
  | { type: 'venue'; item: AdminVenue | null }
  | { type: 'style'; item: AdminStyle | null }
  | { type: 'level'; item: AdminLevel | null }
  | null

function nullable(value: string) {
  const trimmed = value.trim()
  return trimmed || null
}

function nullableNumber(value: string) {
  if (!value.trim()) return null
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

function dancerName(dancer: AdminDancer) {
  if (dancer.custom_name?.trim()) return dancer.custom_name.trim()
  const full = [dancer.first_name, dancer.last_name]
    .filter(Boolean)
    .join(' ')
    .trim()
  if (full) return full
  return dancer.telegram_username ? `@${dancer.telegram_username}` : 'Без имени'
}

function styleName(style: AdminStyle) {
  return style.title_ru?.trim()
    || style.title_en?.trim()
    || style.title_sr?.trim()
    || `Стиль ${style.id}`
}

function levelName(level: AdminLevel) {
  const title = level.title_en || level.title_ru || level.code
  if (level.kind !== 'competition') return title
  return level.is_sport_achievement ? `🏆 ${title}` : title
}

function competitionSystemLabel(system: string) {
  if (system === 'wsdc') return 'WSDC'
  if (system === 'ash_pair') return 'АСХ · Пары'
  if (system === 'ash_jnj') return 'АСХ · JnJ'
  return system
}

function roleName(isLeader: boolean) {
  return isLeader ? 'Leader' : 'Follower'
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat('ru-RU', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Europe/Belgrade',
  }).format(new Date(value)).replace('.', '')
}

function AdminSheet({
  title,
  eyebrow,
  onClose,
  children,
}: {
  title: string
  eyebrow: string
  onClose: () => void
  children: ReactNode
}) {
  return (
    <div className="sheet-backdrop admin-sheet-backdrop" onMouseDown={onClose}>
      <section
        className="sheet admin-sheet tgui-split-sheet"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="tgui-sheet-controls">
          <div className="sheet-handle" />
          <div className="sheet-title-row">
            <div>
              <div className="eyebrow">{eyebrow}</div>
              <h3>{title}</h3>
            </div>
            <SheetCloseButton onClick={onClose} />
          </div>
        </div>

        <div className="tgui-sheet-scroll admin-sheet-scroll">
          {children}
        </div>
      </section>
    </div>
  )
}

function Field({
  label,
  children,
}: {
  label: string
  children: ReactNode
}) {
  return (
    <TelegramFormField label={label}>
      {children}
    </TelegramFormField>
  )
}

function CheckField({
  label,
  checked,
  disabled = false,
  onChange,
}: {
  label: string
  checked: boolean
  disabled?: boolean
  onChange: (value: boolean) => void
}) {
  return (
    <div className="tgui-form-toggle-row admin-toggle-row">
      <span>{label}</span>
      <TelegramSwitch
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.currentTarget.checked)}
      />
    </div>
  )
}

function FormSection({
  header,
  children,
}: {
  header?: string
  children: ReactNode
}) {
  return (
    <Section className="tgui-section admin-form-section" header={header}>
      <div className="tgui-form-panel tgui-form-panel-grid">
        {children}
      </div>
    </Section>
  )
}

function ErrorBlock({ error }: { error: string | null }) {
  return error ? <div className="tgui-error admin-form-error">{error}</div> : null
}

function DancerEditor({
  dancer,
  catalog,
  onClose,
  onSaved,
}: {
  dancer: AdminDancer | null
  catalog: AdminCatalog
  onClose: () => void
  onSaved: () => Promise<void>
}) {
  const [firstName, setFirstName] = useState(dancer?.first_name ?? '')
  const [lastName, setLastName] = useState(dancer?.last_name ?? '')
  const [customName, setCustomName] = useState(dancer?.custom_name ?? '')
  const [username, setUsername] = useState(dancer?.telegram_username ?? '')
  const [telegramId, setTelegramId] = useState(
    dancer?.telegram_id === null || dancer?.telegram_id === undefined
      ? ''
      : String(dancer.telegram_id),
  )
  const [langCode, setLangCode] = useState(dancer?.lang_code ?? 'ru')
  const [primaryRole, setPrimaryRole] = useState(
    dancer?.primary_role ? String(dancer.primary_role) : '',
  )
  const [administrator, setAdministrator] = useState(
    dancer?.roles.includes('administrator') ?? false,
  )
  const [profiles, setProfiles] = useState<AdminDancerStyleProfile[]>(
    dancer?.profiles.map((profile) => ({
      ...profile,
      competition_profiles: profile.competition_profiles.map((item) => ({ ...item })),
    })) ?? [],
  )
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const trainingLevels = (styleId: number) =>
    catalog.levels.filter(
      (level) =>
        level.style_id === styleId
        && level.kind === 'training'
        && level.active,
    )

  const competitionSystems = (styleId: number) =>
    Array.from(
      new Set(
        catalog.levels
          .filter(
            (level) =>
              level.style_id === styleId
              && level.kind === 'competition'
              && level.active,
          )
          .map((level) => level.system_code),
      ),
    )

  const findProfile = (styleId: number, isLeader: boolean) =>
    profiles.find(
      (profile) =>
        profile.style_id === styleId
        && profile.is_leader === isLeader,
    )

  const setRoleEnabled = (
    styleId: number,
    isLeader: boolean,
    enabled: boolean,
  ) => {
    setProfiles((current) => {
      const existing = current.find(
        (profile) =>
          profile.style_id === styleId
          && profile.is_leader === isLeader,
      )

      if (enabled) {
        if (existing) return current
        const hasStyleProfile = current.some((profile) => profile.style_id === styleId)
        return [
          ...current,
          {
            id: null,
            style_id: styleId,
            is_leader: isLeader,
            is_trainer: false,
            is_default: !hasStyleProfile,
            training_level_id: null,
            competition_profiles: [],
          },
        ]
      }

      const next = current.filter(
        (profile) =>
          !(
            profile.style_id === styleId
            && profile.is_leader === isLeader
          ),
      )

      if (existing?.is_default) {
        const replacementIndex = next.findIndex(
          (profile) => profile.style_id === styleId,
        )
        if (replacementIndex >= 0) {
          next[replacementIndex] = {
            ...next[replacementIndex],
            is_default: true,
          }
        }
      }

      return next
    })
  }

  const patchProfile = (
    styleId: number,
    isLeader: boolean,
    patch: Partial<AdminDancerStyleProfile>,
  ) => {
    setProfiles((current) =>
      current.map((profile) =>
        profile.style_id === styleId && profile.is_leader === isLeader
          ? { ...profile, ...patch }
          : profile,
      ),
    )
  }

  const setDefaultRole = (styleId: number, isLeader: boolean) => {
    setProfiles((current) =>
      current.map((profile) =>
        profile.style_id === styleId
          ? {
              ...profile,
              is_default: profile.is_leader === isLeader,
            }
          : profile,
      ),
    )
  }

  const patchCompetition = (
    profile: AdminDancerStyleProfile,
    systemCode: string,
    levelId: number | null,
  ) => {
    const existing = profile.competition_profiles.find(
      (item) => item.system_code === systemCode,
    )

    const competition_profiles = levelId === null
      ? profile.competition_profiles.filter(
          (item) => item.system_code !== systemCode,
        )
      : [
          ...profile.competition_profiles.filter(
            (item) => item.system_code !== systemCode,
          ),
          {
            id: existing?.id ?? null,
            system_code: systemCode,
            level_id: levelId,
            points: existing?.points ?? null,
            external_profile_id: existing?.external_profile_id ?? null,
            last_synced_at: existing?.last_synced_at ?? null,
          },
        ]

    patchProfile(profile.style_id, profile.is_leader, {
      competition_profiles,
    })
  }

  const patchCompetitionMeta = (
    profile: AdminDancerStyleProfile,
    systemCode: string,
    patch: Partial<AdminCompetitionProfile>,
  ) => {
    patchProfile(profile.style_id, profile.is_leader, {
      competition_profiles: profile.competition_profiles.map((item) =>
        item.system_code === systemCode ? { ...item, ...patch } : item,
      ),
    })
  }

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setSaving(true)
    setError(null)

    try {
      await saveAdminDancer(dancer?.id ?? null, {
        telegram_id: nullableNumber(telegramId),
        telegram_username: nullable(username),
        first_name: nullable(firstName),
        last_name: nullable(lastName),
        custom_name: nullable(customName),
        lang_code: langCode.trim() || 'ru',
        primary_role: nullableNumber(primaryRole),
        is_administrator: administrator,
        profiles: profiles.map((profile) => ({
          style_id: profile.style_id,
          is_leader: profile.is_leader,
          is_trainer: profile.is_trainer,
          is_default: profile.is_default,
          training_level_id: profile.training_level_id,
          competition_profiles: profile.competition_profiles.map((item) => ({
            system_code: item.system_code,
            level_id: item.level_id,
            points: item.points,
            external_profile_id: item.external_profile_id,
            last_synced_at: item.last_synced_at,
          })),
        })),
      })
      await onSaved()
      onClose()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AdminSheet
      title={dancer ? dancerName(dancer) : 'Новый танцор'}
      eyebrow="Администратор · Танцоры"
      onClose={onClose}
    >
      <form onSubmit={submit}>
        <FormSection>
          {dancer && !dancer.auth_linked ? (
            <div className="admin-inline-note">
              Профиль ещё не привязан к Telegram Auth.
              {dancer.telegram_id
                ? ' При первом входе с этим Telegram ID связь создастся автоматически.'
                : ' Для автоматической привязки нужен Telegram ID.'}
            </div>
          ) : null}

          <div className="two-col">
            <Field label="Имя">
              <TelegramInput value={firstName} onChange={(event) => setFirstName(event.target.value)} />
            </Field>
            <Field label="Фамилия">
              <TelegramInput value={lastName} onChange={(event) => setLastName(event.target.value)} />
            </Field>
          </div>

          <Field label="Отображаемое имя">
            <TelegramInput
              value={customName}
              onChange={(event) => setCustomName(event.target.value)}
              placeholder="Если отличается от имени и фамилии"
            />
          </Field>

          <div className="two-col">
            <Field label="Telegram username">
              <TelegramInput
                value={username}
                onChange={(event) => setUsername(event.target.value.replace(/^@/, ''))}
                placeholder="username"
              />
            </Field>
            <Field label="Telegram ID">
              <TelegramInput
                inputMode="numeric"
                value={telegramId}
                disabled={dancer?.auth_linked === true}
                onChange={(event) => setTelegramId(event.target.value)}
                placeholder="Необязательно"
              />
            </Field>
          </div>

          <div className="two-col">
            <Field label="Основная роль">
              <TelegramSelect
                value={primaryRole}
                onChange={(event) => setPrimaryRole(event.target.value)}
              >
                <option value="">Не выбрана</option>
                <option value="1">Leader</option>
                <option value="2">Follower</option>
              </TelegramSelect>
            </Field>
            <Field label="Язык">
              <TelegramInput
                value={langCode}
                onChange={(event) => setLangCode(event.target.value)}
                placeholder="ru"
              />
            </Field>
          </div>

          <CheckField
            label="Администратор"
            checked={administrator}
            onChange={setAdministrator}
          />
        </FormSection>

        <div className="admin-editor-heading">
          <strong>Стили</strong>
          <span>Тренерство и классы настраиваются здесь же.</span>
        </div>

        {catalog.styles.map((style) => {
          const roles = style.is_partner_dance
            ? [
                { isLeader: false, label: 'Follower' },
                { isLeader: true, label: 'Leader' },
              ]
            : [{ isLeader: false, label: 'Танцор' }]

          return (
            <Section
              className="tgui-section admin-style-section"
              key={style.id}
              header={styleName(style)}
              footer={style.is_partner_dance ? 'Парный стиль' : 'Соло'}
            >
              <div className="tgui-form-panel admin-style-panel">
              {roles.map(({ isLeader, label }) => {
                const profile = findProfile(style.id, isLeader)
                const enabled = Boolean(profile)

                return (
                  <div className="admin-role-profile" key={label}>
                    <CheckField
                      label={label}
                      checked={enabled}
                      onChange={(value) => setRoleEnabled(style.id, isLeader, value)}
                    />

                    {profile ? (
                      <div className="admin-role-profile-fields">
                        <div className="admin-profile-flags">
                          <CheckField
                            label="По умолчанию"
                            checked={profile.is_default}
                            onChange={(value) => {
                              if (value) setDefaultRole(style.id, isLeader)
                            }}
                          />
                          <CheckField
                            label="Тренер"
                            checked={profile.is_trainer}
                            onChange={(value) =>
                              patchProfile(style.id, isLeader, {
                                is_trainer: value,
                              })
                            }
                          />
                        </div>

                        <Field label="Учебный уровень">
                          <TelegramSelect
                            value={profile.training_level_id ?? ''}
                            onChange={(event) =>
                              patchProfile(style.id, isLeader, {
                                training_level_id: nullableNumber(event.target.value),
                              })
                            }
                          >
                            <option value="">Не указан</option>
                            {trainingLevels(style.id).map((level) => (
                              <option key={level.id} value={level.id}>
                                {level.title_en}
                              </option>
                            ))}
                          </TelegramSelect>
                        </Field>

                        {competitionSystems(style.id).map((systemCode) => {
                          const levels = catalog.levels.filter(
                            (level) =>
                              level.style_id === style.id
                              && level.kind === 'competition'
                              && level.system_code === systemCode
                              && level.active,
                          )
                          const competition = profile.competition_profiles.find(
                            (item) => item.system_code === systemCode,
                          )

                          return (
                            <div className="admin-competition-block" key={systemCode}>
                              <Field label={competitionSystemLabel(systemCode)}>
                                <TelegramSelect
                                  value={competition?.level_id ?? ''}
                                  onChange={(event) =>
                                    patchCompetition(
                                      profile,
                                      systemCode,
                                      nullableNumber(event.target.value),
                                    )
                                  }
                                >
                                  <option value="">Нет класса</option>
                                  {levels.map((level) => (
                                    <option key={level.id} value={level.id}>
                                      {levelName(level)}
                                    </option>
                                  ))}
                                </TelegramSelect>
                              </Field>

                              {competition ? (
                                <div className="two-col">
                                  <Field label="Очки">
                                    <TelegramInput
                                      inputMode="decimal"
                                      value={competition.points ?? ''}
                                      onChange={(event) =>
                                        patchCompetitionMeta(profile, systemCode, {
                                          points: nullableNumber(event.target.value),
                                        })
                                      }
                                    />
                                  </Field>
                                  <Field label="External ID">
                                    <TelegramInput
                                      value={competition.external_profile_id ?? ''}
                                      onChange={(event) =>
                                        patchCompetitionMeta(profile, systemCode, {
                                          external_profile_id: nullable(event.target.value),
                                        })
                                      }
                                    />
                                  </Field>
                                </div>
                              ) : null}
                            </div>
                          )
                        })}
                      </div>
                    ) : null}
                  </div>
                )
              })}
              </div>
            </Section>
          )
        })}

        <ErrorBlock error={error} />
        <Button
          type="submit"
          stretched
          loading={saving}
          disabled={saving}
          className="admin-save-button"
        >
          Сохранить танцора
        </Button>
      </form>
    </AdminSheet>
  )
}

function GroupEditor({
  group,
  catalog,
  onClose,
  onSaved,
}: {
  group: AdminGroup | null
  catalog: AdminCatalog
  onClose: () => void
  onSaved: () => Promise<void>
}) {
  const initialStyle = group?.style_id ?? catalog.styles[0]?.id ?? 0
  const [styleId, setStyleId] = useState(initialStyle)
  const [levelId, setLevelId] = useState(
    group?.level_id === null || group?.level_id === undefined
      ? ''
      : String(group.level_id),
  )
  const [trainerId, setTrainerId] = useState(group?.lead_trainer_id ?? '')
  const [description, setDescription] = useState(group?.description ?? '')
  const [capacity, setCapacity] = useState(
    group?.max_capacity === null || group?.max_capacity === undefined
      ? ''
      : String(group.max_capacity),
  )
  const [approvalRequired, setApprovalRequired] = useState(group?.approval_required ?? false)
  const [enrollment, setEnrollment] = useState(group?.enrollment_status ?? 'open')
  const [startsOn, setStartsOn] = useState(group?.starts_on ?? '')
  const [endsOn, setEndsOn] = useState(group?.ends_on ?? '')
  const [active, setActive] = useState(group?.active ?? true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const levels = catalog.levels.filter(
    (level) => level.style_id === styleId && level.active,
  )
  const trainerCandidates = catalog.dancers.filter(
    (dancer) =>
      dancer.id === trainerId
      || dancer.profiles.some(
        (profile) =>
          profile.style_id === styleId
          && profile.is_trainer,
      ),
  )

  useEffect(() => {
    if (levelId && !levels.some((level) => String(level.id) === levelId)) {
      setLevelId('')
    }
    if (
      trainerId
      && !trainerCandidates.some((dancer) => dancer.id === trainerId)
    ) {
      setTrainerId('')
    }
  }, [styleId])

  const preview = [
    styleName(catalog.styles.find((style) => style.id === styleId) ?? {
      id: styleId,
      title_en: 'Стиль',
      title_ru: null,
      title_sr: null,
      is_partner_dance: true,
    }),
    levels.find((level) => String(level.id) === levelId)?.title_en,
    trainerCandidates.find((dancer) => dancer.id === trainerId)
      ? dancerName(trainerCandidates.find((dancer) => dancer.id === trainerId)!)
      : null,
  ].filter(Boolean).join(' · ')

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!styleId) return

    setSaving(true)
    setError(null)
    try {
      await saveAdminGroup({
        id: group?.id ?? null,
        style_id: styleId,
        description: nullable(description),
        level_id: nullableNumber(levelId),
        max_capacity: nullableNumber(capacity),
        approval_required: approvalRequired,
        enrollment_status: enrollment,
        starts_on: nullable(startsOn),
        ends_on: nullable(endsOn),
        active,
        lead_trainer_id: nullable(trainerId),
      })
      await onSaved()
      onClose()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AdminSheet
      title={group ? group.title : 'Новая группа'}
      eyebrow="Администратор · Расписание"
      onClose={onClose}
    >
      <form onSubmit={submit}>
        <FormSection>
          <Field label="Стиль">
            <TelegramSelect
              value={styleId}
              onChange={(event) => setStyleId(Number(event.target.value))}
            >
              {catalog.styles.map((style) => (
                <option key={style.id} value={style.id}>
                  {styleName(style)}
                </option>
              ))}
            </TelegramSelect>
          </Field>

          <Field label="Уровень">
            <TelegramSelect value={levelId} onChange={(event) => setLevelId(event.target.value)}>
              <option value="">Без уровня</option>
              {levels.map((level) => (
                <option key={level.id} value={level.id}>
                  {level.kind === 'competition'
                    ? `${levelName(level)} · ${competitionSystemLabel(level.system_code)}`
                    : level.title_en}
                </option>
              ))}
            </TelegramSelect>
          </Field>

          <Field label="Главный тренер">
            <TelegramSelect value={trainerId} onChange={(event) => setTrainerId(event.target.value)}>
              <option value="">Не назначен</option>
              {trainerCandidates.map((dancer) => (
                <option key={dancer.id} value={dancer.id}>
                  {dancerName(dancer)}
                </option>
              ))}
            </TelegramSelect>
          </Field>

          <div className="admin-generated-preview">
            <span>Название группы</span>
            <strong>{preview || 'Сформируется автоматически'}</strong>
          </div>

          <Field label="Описание">
            <TelegramTextarea
              rows={3}
              value={description}
              onChange={(event) => setDescription(event.target.value)}
            />
          </Field>

          <div className="two-col">
            <Field label="Максимум человек">
              <TelegramInput
                inputMode="numeric"
                value={capacity}
                onChange={(event) => setCapacity(event.target.value)}
              />
            </Field>
            <Field label="Набор">
              <TelegramSelect
                value={enrollment}
                onChange={(event) =>
                  setEnrollment(
                    event.target.value as AdminGroup['enrollment_status'],
                  )
                }
              >
                <option value="open">Открыт</option>
                <option value="closed">Закрыт</option>
                <option value="waitlist_only">Только лист ожидания</option>
                <option value="archived">Архив</option>
              </TelegramSelect>
            </Field>
          </div>

          <div className="two-col">
            <Field label="Начало">
              <TelegramInput type="date" value={startsOn} onChange={(event) => setStartsOn(event.target.value)} />
            </Field>
            <Field label="Окончание">
              <TelegramInput type="date" value={endsOn} onChange={(event) => setEndsOn(event.target.value)} />
            </Field>
          </div>

          <CheckField
            label="Требуется подтверждение"
            checked={approvalRequired}
            onChange={setApprovalRequired}
          />
          <CheckField label="Активна" checked={active} onChange={setActive} />
        </FormSection>

        <ErrorBlock error={error} />
        <Button
          type="submit"
          stretched
          loading={saving}
          disabled={saving}
          className="admin-save-button"
        >
          Сохранить группу
        </Button>
      </form>
    </AdminSheet>
  )
}

function EventEditor({
  event,
  catalog,
  onClose,
  onSaved,
}: {
  event: AdminEvent | null
  catalog: AdminCatalog
  onClose: () => void
  onSaved: () => Promise<void>
}) {
  const [type, setType] = useState<AdminEvent['event_type']>(event?.event_type ?? 'party')
  const [title, setTitle] = useState(event?.title ?? '')
  const [description, setDescription] = useState(event?.description ?? '')
  const [startsLocal, setStartsLocal] = useState(isoToLocalInput(event?.starts_at ?? null))
  const [endsLocal, setEndsLocal] = useState(isoToLocalInput(event?.ends_at ?? null))
  const [venueId, setVenueId] = useState(event?.venue_id ?? '')
  const [styleId, setStyleId] = useState(event?.style_id ? String(event.style_id) : '')
  const [published, setPublished] = useState(event?.published ?? true)
  const [cancelled, setCancelled] = useState(Boolean(event?.cancelled_at))
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (formEvent: FormEvent) => {
    formEvent.preventDefault()
    setSaving(true)
    setError(null)

    try {
      await saveAdminEvent({
        id: event?.id ?? null,
        event_type: type,
        title,
        description: nullable(description),
        starts_local: startsLocal,
        ends_local: endsLocal,
        venue_id: nullable(venueId),
        style_id: nullableNumber(styleId),
        published,
        cancelled,
        existing_cancelled_at: event?.cancelled_at ?? null,
      })
      await onSaved()
      onClose()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AdminSheet
      title={event ? event.title : 'Новое событие'}
      eyebrow="Администратор · Расписание"
      onClose={onClose}
    >
      <form onSubmit={submit}>
        <FormSection>
          <Field label="Тип">
            <TelegramSelect value={type} onChange={(e) => setType(e.target.value as AdminEvent['event_type'])}>
              <option value="party">Вечеринка</option>
              <option value="open_class">Опен</option>
            </TelegramSelect>
          </Field>

          <Field label="Название">
            <TelegramInput required value={title} onChange={(e) => setTitle(e.target.value)} />
          </Field>

          <Field label="Описание">
            <TelegramTextarea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
          </Field>

          <div className="two-col">
            <Field label="Начало">
              <TelegramInput type="datetime-local" required value={startsLocal} onChange={(e) => setStartsLocal(e.target.value)} />
            </Field>
            <Field label="Окончание">
              <TelegramInput type="datetime-local" value={endsLocal} onChange={(e) => setEndsLocal(e.target.value)} />
            </Field>
          </div>

          <Field label="Стиль">
            <TelegramSelect value={styleId} onChange={(e) => setStyleId(e.target.value)}>
              <option value="">Без стиля</option>
              {catalog.styles.map((style) => (
                <option key={style.id} value={style.id}>{styleName(style)}</option>
              ))}
            </TelegramSelect>
          </Field>

          <Field label="Зал">
            <TelegramSelect value={venueId} onChange={(e) => setVenueId(e.target.value)}>
              <option value="">Без зала</option>
              {catalog.venues.filter((venue) => venue.active || venue.id === venueId).map((venue) => (
                <option key={venue.id} value={venue.id}>{venue.name}</option>
              ))}
            </TelegramSelect>
          </Field>

          <CheckField label="Опубликовано" checked={published} onChange={setPublished} />
          <CheckField label="Отменено" checked={cancelled} onChange={setCancelled} />
        </FormSection>

        <ErrorBlock error={error} />
        <Button
          type="submit"
          stretched
          loading={saving}
          disabled={saving}
          className="admin-save-button"
        >
          Сохранить событие
        </Button>
      </form>
    </AdminSheet>
  )
}

function VenueEditor({
  venue,
  onClose,
  onSaved,
}: {
  venue: AdminVenue | null
  onClose: () => void
  onSaved: () => Promise<void>
}) {
  const [name, setName] = useState(venue?.name ?? '')
  const [address, setAddress] = useState(venue?.address ?? '')
  const [latitude, setLatitude] = useState(venue?.latitude === null || venue?.latitude === undefined ? '' : String(venue.latitude))
  const [longitude, setLongitude] = useState(venue?.longitude === null || venue?.longitude === undefined ? '' : String(venue.longitude))
  const [capacity, setCapacity] = useState(venue?.capacity === null || venue?.capacity === undefined ? '' : String(venue.capacity))
  const [notes, setNotes] = useState(venue?.notes ?? '')
  const [active, setActive] = useState(venue?.active ?? true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setSaving(true)
    setError(null)

    try {
      await saveAdminVenue({
        id: venue?.id ?? null,
        name,
        address: nullable(address),
        latitude: nullableNumber(latitude),
        longitude: nullableNumber(longitude),
        capacity: nullableNumber(capacity),
        notes: nullable(notes),
        active,
      })
      await onSaved()
      onClose()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AdminSheet
      title={venue?.name ?? 'Новый зал'}
      eyebrow="Администратор · Настройки"
      onClose={onClose}
    >
      <form onSubmit={submit}>
        <FormSection>
          <Field label="Название">
            <TelegramInput required value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
          <Field label="Адрес">
            <TelegramInput value={address} onChange={(e) => setAddress(e.target.value)} />
          </Field>
          <div className="two-col">
            <Field label="Широта">
              <TelegramInput inputMode="decimal" value={latitude} onChange={(e) => setLatitude(e.target.value)} />
            </Field>
            <Field label="Долгота">
              <TelegramInput inputMode="decimal" value={longitude} onChange={(e) => setLongitude(e.target.value)} />
            </Field>
          </div>
          <Field label="Вместимость">
            <TelegramInput inputMode="numeric" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
          </Field>
          <Field label="Заметки">
            <TelegramTextarea rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </Field>
          <CheckField label="Активен" checked={active} onChange={setActive} />
        </FormSection>
        <ErrorBlock error={error} />
        <Button
          type="submit"
          stretched
          loading={saving}
          disabled={saving}
          className="admin-save-button"
        >
          Сохранить зал
        </Button>
      </form>
    </AdminSheet>
  )
}

function StyleEditor({
  style,
  onClose,
  onSaved,
}: {
  style: AdminStyle | null
  onClose: () => void
  onSaved: () => Promise<void>
}) {
  const [titleEn, setTitleEn] = useState(style?.title_en ?? '')
  const [titleRu, setTitleRu] = useState(style?.title_ru ?? '')
  const [titleSr, setTitleSr] = useState(style?.title_sr ?? '')
  const [partner, setPartner] = useState(style?.is_partner_dance ?? true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setSaving(true)
    setError(null)
    try {
      await saveAdminStyle(style?.id ?? null, {
        title_en: nullable(titleEn),
        title_ru: nullable(titleRu),
        title_sr: nullable(titleSr),
        is_partner_dance: partner,
      })
      await onSaved()
      onClose()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AdminSheet
      title={style ? styleName(style) : 'Новый стиль'}
      eyebrow="Администратор · Настройки"
      onClose={onClose}
    >
      <form onSubmit={submit}>
        <FormSection>
          <Field label="Название EN">
            <TelegramInput required value={titleEn} onChange={(e) => setTitleEn(e.target.value)} />
          </Field>
          <Field label="Название RU">
            <TelegramInput value={titleRu} onChange={(e) => setTitleRu(e.target.value)} />
          </Field>
          <Field label="Название SR">
            <TelegramInput value={titleSr} onChange={(e) => setTitleSr(e.target.value)} />
          </Field>
          <CheckField label="Парный стиль" checked={partner} onChange={setPartner} />
        </FormSection>
        <ErrorBlock error={error} />
        <Button
          type="submit"
          stretched
          loading={saving}
          disabled={saving}
          className="admin-save-button"
        >
          Сохранить стиль
        </Button>
      </form>
    </AdminSheet>
  )
}

function LevelEditor({
  level,
  catalog,
  onClose,
  onSaved,
}: {
  level: AdminLevel | null
  catalog: AdminCatalog
  onClose: () => void
  onSaved: () => Promise<void>
}) {
  const [styleId, setStyleId] = useState(level?.style_id ?? catalog.styles[0]?.id ?? 0)
  const [kind, setKind] = useState<AdminLevel['kind']>(level?.kind ?? 'training')
  const [systemCode, setSystemCode] = useState(level?.system_code ?? 'school')
  const [code, setCode] = useState(level?.code ?? '')
  const [titleEn, setTitleEn] = useState(level?.title_en ?? '')
  const [titleRu, setTitleRu] = useState(level?.title_ru ?? '')
  const [titleSr, setTitleSr] = useState(level?.title_sr ?? '')
  const [rank, setRank] = useState(level ? String(level.rank_order) : '0')
  const [sport, setSport] = useState(level?.is_sport_achievement ?? false)
  const [description, setDescription] = useState(level?.description ?? '')
  const [active, setActive] = useState(level?.active ?? true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (kind === 'training') {
      setSystemCode('school')
      setSport(false)
    }
  }, [kind])

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setSaving(true)
    setError(null)
    try {
      await saveAdminLevel(level?.id ?? null, {
        style_id: styleId,
        code: code.trim(),
        title_en: titleEn.trim(),
        title_ru: nullable(titleRu),
        title_sr: nullable(titleSr),
        rank_order: nullableNumber(rank) ?? 0,
        active,
        kind,
        system_code: systemCode.trim() || 'school',
        is_sport_achievement: sport,
        description: nullable(description),
      })
      await onSaved()
      onClose()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <AdminSheet
      title={level ? levelName(level) : 'Новый уровень'}
      eyebrow="Администратор · Настройки"
      onClose={onClose}
    >
      <form onSubmit={submit}>
        <FormSection>
          <Field label="Стиль">
            <TelegramSelect value={styleId} onChange={(e) => setStyleId(Number(e.target.value))}>
              {catalog.styles.map((style) => (
                <option key={style.id} value={style.id}>{styleName(style)}</option>
              ))}
            </TelegramSelect>
          </Field>
          <div className="two-col">
            <Field label="Тип">
              <TelegramSelect value={kind} onChange={(e) => setKind(e.target.value as AdminLevel['kind'])}>
                <option value="training">Учебный</option>
                <option value="competition">Соревновательный</option>
              </TelegramSelect>
            </Field>
            <Field label="Система">
              <TelegramInput
                value={systemCode}
                disabled={kind === 'training'}
                onChange={(e) => setSystemCode(e.target.value)}
                placeholder="wsdc / ash_pair"
              />
            </Field>
          </div>
          <div className="two-col">
            <Field label="Code">
              <TelegramInput required value={code} onChange={(e) => setCode(e.target.value)} />
            </Field>
            <Field label="Порядок">
              <TelegramInput inputMode="numeric" value={rank} onChange={(e) => setRank(e.target.value)} />
            </Field>
          </div>
          <Field label="Название EN">
            <TelegramInput required value={titleEn} onChange={(e) => setTitleEn(e.target.value)} />
          </Field>
          <Field label="Название RU">
            <TelegramInput value={titleRu} onChange={(e) => setTitleRu(e.target.value)} />
          </Field>
          <Field label="Название SR">
            <TelegramInput value={titleSr} onChange={(e) => setTitleSr(e.target.value)} />
          </Field>
          <Field label="Описание">
            <TelegramTextarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
          </Field>
          {kind === 'competition' ? (
            <CheckField
              label="🏆 Заработанный спортивный класс"
              checked={sport}
              onChange={setSport}
            />
          ) : null}
          <CheckField label="Активен" checked={active} onChange={setActive} />
        </FormSection>
        <ErrorBlock error={error} />
        <Button
          type="submit"
          stretched
          loading={saving}
          disabled={saving}
          className="admin-save-button"
        >
          Сохранить уровень
        </Button>
      </form>
    </AdminSheet>
  )
}

function DancersPage({
  catalog,
  onEdit,
}: {
  catalog: AdminCatalog
  onEdit: (dancer: AdminDancer | null) => void
}) {
  const [query, setQuery] = useState('')
  const needle = query.trim().toLocaleLowerCase('ru')
  const dancers = needle
    ? catalog.dancers.filter((dancer) =>
        [
          dancerName(dancer),
          dancer.telegram_username,
          dancer.telegram_id ? String(dancer.telegram_id) : null,
        ]
          .filter(Boolean)
          .some((value) => String(value).toLocaleLowerCase('ru').includes(needle)),
      )
    : catalog.dancers

  return (
    <section className="tgui-page admin-page">
      <div className="admin-page-actions">
        <TelegramInput
          className="admin-search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Поиск танцора"
        />
        <Button size="s" onClick={() => onEdit(null)}>+ Танцор</Button>
      </div>

      <Section className="tgui-section">
        <List className="tgui-trip-list">
          {dancers.map((dancer) => {
            const styles = Array.from(new Set(
              dancer.profiles.map((profile) =>
                styleName(
                  catalog.styles.find((style) => style.id === profile.style_id)
                  ?? {
                    id: profile.style_id,
                    title_en: `Стиль ${profile.style_id}`,
                    title_ru: null,
                    title_sr: null,
                    is_partner_dance: true,
                  },
                ),
              ),
            ))
            const trainer = dancer.profiles.some((profile) => profile.is_trainer)

            return (
              <Cell
                key={dancer.id}
                Component="button"
                className="tgui-trip-cell admin-list-cell"
                hint={trainer ? 'Тренер' : undefined}
                subtitle={
                  dancer.telegram_username
                    ? `@${dancer.telegram_username}`
                    : dancer.telegram_id
                      ? `Telegram ${dancer.telegram_id}`
                      : 'Telegram не привязан'
                }
                description={[
                  dancer.roles.includes('administrator') ? 'Администратор' : null,
                  styles.join(' · ') || null,
                ].filter(Boolean).join(' · ') || undefined}
                after={<span className="menu-chevron">›</span>}
                onClick={() => onEdit(dancer)}
              >
                {dancerName(dancer)}
              </Cell>
            )
          })}
        </List>
      </Section>
    </section>
  )
}

function SchedulePage({
  catalog,
  onEditGroup,
  onEditEvent,
}: {
  catalog: AdminCatalog
  onEditGroup: (group: AdminGroup | null) => void
  onEditEvent: (event: AdminEvent | null) => void
}) {
  const [view, setView] = useState<'groups' | 'events'>('groups')

  return (
    <section className="tgui-page admin-page">
      <div className="admin-tabs-with-action">
        <TabsList className="tgui-city-tabs admin-local-tabs">
          <TabsList.Item selected={view === 'groups'} onClick={() => setView('groups')}>
            Группы
          </TabsList.Item>
          <TabsList.Item selected={view === 'events'} onClick={() => setView('events')}>
            События
          </TabsList.Item>
        </TabsList>
        <Button
          size="s"
          onClick={() => view === 'groups' ? onEditGroup(null) : onEditEvent(null)}
        >
          + {view === 'groups' ? 'Группа' : 'Событие'}
        </Button>
      </div>

      {view === 'groups' ? (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {catalog.groups.map((group) => {
              const level = catalog.levels.find((item) => item.id === group.level_id)
              const trainer = catalog.dancers.find((item) => item.id === group.lead_trainer_id)
              return (
                <Cell
                  key={group.id}
                  Component="button"
                  className="tgui-trip-cell admin-list-cell"
                  hint={group.active ? 'Активна' : 'Выключена'}
                  subtitle={[
                    level ? levelName(level) : null,
                    trainer ? dancerName(trainer) : null,
                  ].filter(Boolean).join(' · ') || undefined}
                  description={[
                    group.enrollment_status === 'open' ? 'Набор открыт' : group.enrollment_status,
                    group.max_capacity ? `до ${group.max_capacity} человек` : null,
                  ].filter(Boolean).join(' · ') || undefined}
                  after={<span className="menu-chevron">›</span>}
                  onClick={() => onEditGroup(group)}
                >
                  {group.title}
                </Cell>
              )
            })}
          </List>
        </Section>
      ) : (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {catalog.events.map((event) => (
              <Cell
                key={event.id}
                Component="button"
                className="tgui-trip-cell admin-list-cell"
                hint={
                  event.cancelled_at
                    ? 'Отменено'
                    : event.published
                      ? 'Опубликовано'
                      : 'Черновик'
                }
                subtitle={dateTimeLabel(event.starts_at)}
                description={[
                  event.event_type === 'party' ? 'Вечеринка' : 'Опен',
                  catalog.venues.find((venue) => venue.id === event.venue_id)?.name,
                ].filter(Boolean).join(' · ') || undefined}
                after={<span className="menu-chevron">›</span>}
                onClick={() => onEditEvent(event)}
              >
                {event.title}
              </Cell>
            ))}
          </List>
        </Section>
      )}
    </section>
  )
}

function SettingsPage({
  catalog,
  onEditVenue,
  onEditStyle,
  onEditLevel,
}: {
  catalog: AdminCatalog
  onEditVenue: (venue: AdminVenue | null) => void
  onEditStyle: (style: AdminStyle | null) => void
  onEditLevel: (level: AdminLevel | null) => void
}) {
  const [view, setView] = useState<'venues' | 'styles' | 'levels'>('venues')

  return (
    <section className="tgui-page admin-page">
      <div className="admin-tabs-with-action">
        <TabsList className="tgui-city-tabs admin-local-tabs">
          <TabsList.Item selected={view === 'venues'} onClick={() => setView('venues')}>Залы</TabsList.Item>
          <TabsList.Item selected={view === 'styles'} onClick={() => setView('styles')}>Стили</TabsList.Item>
          <TabsList.Item selected={view === 'levels'} onClick={() => setView('levels')}>Уровни</TabsList.Item>
        </TabsList>
        <Button
          size="s"
          onClick={() => {
            if (view === 'venues') onEditVenue(null)
            if (view === 'styles') onEditStyle(null)
            if (view === 'levels') onEditLevel(null)
          }}
        >
          + Добавить
        </Button>
      </div>

      {view === 'venues' ? (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {catalog.venues.map((venue) => (
              <Cell
                key={venue.id}
                Component="button"
                className="tgui-trip-cell admin-list-cell"
                hint={venue.active ? undefined : 'Выключен'}
                subtitle={venue.address ?? undefined}
                description={venue.capacity ? `до ${venue.capacity} человек` : undefined}
                after={<span className="menu-chevron">›</span>}
                onClick={() => onEditVenue(venue)}
              >
                {venue.name}
              </Cell>
            ))}
          </List>
        </Section>
      ) : null}

      {view === 'styles' ? (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {catalog.styles.map((style) => (
              <Cell
                key={style.id}
                Component="button"
                className="tgui-trip-cell admin-list-cell"
                hint={style.is_partner_dance ? 'Парный' : 'Соло'}
                description={
                  catalog.levels.filter((level) => level.style_id === style.id && level.active).length
                    ? `${catalog.levels.filter((level) => level.style_id === style.id && level.active).length} уровней`
                    : 'Уровни не настроены'
                }
                after={<span className="menu-chevron">›</span>}
                onClick={() => onEditStyle(style)}
              >
                {styleName(style)}
              </Cell>
            ))}
          </List>
        </Section>
      ) : null}

      {view === 'levels' ? (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {catalog.levels.map((level) => {
              const style = catalog.styles.find((item) => item.id === level.style_id)
              return (
                <Cell
                  key={level.id}
                  Component="button"
                  className="tgui-trip-cell admin-list-cell"
                  hint={level.active ? undefined : 'Выключен'}
                  subtitle={[
                    style ? styleName(style) : null,
                    level.kind === 'training'
                      ? 'Учебный'
                      : competitionSystemLabel(level.system_code),
                  ].filter(Boolean).join(' · ') || undefined}
                  description={
                    level.is_sport_achievement ? '🏆 Спортивный класс' : undefined
                  }
                  after={<span className="menu-chevron">›</span>}
                  onClick={() => onEditLevel(level)}
                >
                  {levelName(level)}
                </Cell>
              )
            })}
          </List>
        </Section>
      ) : null}
    </section>
  )
}

export default function AdminProfile({ view }: { view: AdminView }) {
  const [state, setState] = useState<LoadState>({
    status: 'loading',
    data: null,
    error: null,
  })
  const [editor, setEditor] = useState<EditorState>(null)

  const refresh = async () => {
    const data = await loadAdminCatalog()
    setState({ status: 'ready', data, error: null })
  }

  useEffect(() => {
    let cancelled = false
    setState({ status: 'loading', data: null, error: null })

    void loadAdminCatalog()
      .then((data) => {
        if (!cancelled) setState({ status: 'ready', data, error: null })
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setState({
            status: 'error',
            data: null,
            error: error instanceof Error ? error.message : String(error),
          })
        }
      })

    return () => {
      cancelled = true
    }
  }, [])

  const title = useMemo(() => {
    if (view === 'dancers') return 'Танцоры'
    if (view === 'schedule') return 'Расписание'
    return 'Настройки'
  }, [view])

  if (state.status === 'loading') {
    return (
      <section className="tgui-page admin-page">
        <Placeholder header={`Загружаю: ${title}`}>
          <Spinner size="m" />
        </Placeholder>
      </section>
    )
  }

  if (state.status === 'error') {
    return (
      <section className="tgui-page admin-page">
        <Placeholder
          header="Не удалось загрузить админ-профиль"
          description={state.error}
        />
      </section>
    )
  }

  const catalog = state.data

  return (
    <>
      {view === 'dancers' ? (
        <DancersPage
          catalog={catalog}
          onEdit={(item) => setEditor({ type: 'dancer', item })}
        />
      ) : null}

      {view === 'schedule' ? (
        <SchedulePage
          catalog={catalog}
          onEditGroup={(item) => setEditor({ type: 'group', item })}
          onEditEvent={(item) => setEditor({ type: 'event', item })}
        />
      ) : null}

      {view === 'settings' ? (
        <SettingsPage
          catalog={catalog}
          onEditVenue={(item) => setEditor({ type: 'venue', item })}
          onEditStyle={(item) => setEditor({ type: 'style', item })}
          onEditLevel={(item) => setEditor({ type: 'level', item })}
        />
      ) : null}

      {editor?.type === 'dancer' ? (
        <DancerEditor
          key={editor.item?.id ?? 'new-dancer'}
          dancer={editor.item}
          catalog={catalog}
          onClose={() => setEditor(null)}
          onSaved={refresh}
        />
      ) : null}

      {editor?.type === 'group' ? (
        <GroupEditor
          key={editor.item?.id ?? 'new-group'}
          group={editor.item}
          catalog={catalog}
          onClose={() => setEditor(null)}
          onSaved={refresh}
        />
      ) : null}

      {editor?.type === 'event' ? (
        <EventEditor
          key={editor.item?.id ?? 'new-event'}
          event={editor.item}
          catalog={catalog}
          onClose={() => setEditor(null)}
          onSaved={refresh}
        />
      ) : null}

      {editor?.type === 'venue' ? (
        <VenueEditor
          key={editor.item?.id ?? 'new-venue'}
          venue={editor.item}
          onClose={() => setEditor(null)}
          onSaved={refresh}
        />
      ) : null}

      {editor?.type === 'style' ? (
        <StyleEditor
          key={editor.item?.id ?? 'new-style'}
          style={editor.item}
          onClose={() => setEditor(null)}
          onSaved={refresh}
        />
      ) : null}

      {editor?.type === 'level' ? (
        <LevelEditor
          key={editor.item?.id ?? 'new-level'}
          level={editor.item}
          catalog={catalog}
          onClose={() => setEditor(null)}
          onSaved={refresh}
        />
      ) : null}
    </>
  )
}
