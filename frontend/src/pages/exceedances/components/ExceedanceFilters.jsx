import { useEffect, useState } from 'react'
import { FilterPanel } from '../../../components/common/Card.jsx'
import { Field, Input, Select } from '../../../components/common/FormField.jsx'
import { usePollutantMeta, useStationOptions } from '../../../hooks/useOptions.js'

const STATUS_OPTIONS = [
  { value: 'pending', label: '待标注' },
  { value: 'confirmed', label: '已确认' },
  { value: 'ignored', label: '已忽略' }
]

const LEVEL_OPTIONS = [
  { value: 'light', label: '轻度超标' },
  { value: 'moderate', label: '中度超标' },
  { value: 'severe', label: '重度超标' }
]

export default function ExceedanceFilters({ value, loading, onSubmit, onReset }) {
  const [draft, setDraft] = useState(value)
  const { data: stationData } = useStationOptions()
  const { data: pollutantData } = usePollutantMeta()

  useEffect(() => {
    setDraft(value)
  }, [value])

  const update = (key) => (event) => setDraft({ ...draft, [key]: event.target.value })

  return (
    <FilterPanel
      loading={loading}
      onSearch={() => onSubmit(draft)}
      onReset={() => {
        setDraft({ status: '', level: '', pollutant: '', station_id: '', date_from: '', date_to: '', keyword: '' })
        onReset()
      }}
    >
      <Field label="标注状态">
        <Select value={draft.status || ''} onChange={update('status')} placeholder="全部状态" options={STATUS_OPTIONS} />
      </Field>
      <Field label="超标等级">
        <Select value={draft.level || ''} onChange={update('level')} placeholder="全部等级" options={LEVEL_OPTIONS} />
      </Field>
      <Field label="监测点">
        <Select
          value={draft.station_id || ''}
          onChange={update('station_id')}
          placeholder="全部监测点"
          options={(stationData?.items ?? []).map((item) => ({ value: String(item.id), label: `${item.code} ${item.name}` }))}
        />
      </Field>
      <Field label="监测因子">
        <Select
          value={draft.pollutant || ''}
          onChange={update('pollutant')}
          placeholder="全部因子"
          options={(pollutantData?.items ?? []).map((item) => ({ value: item.code, label: item.label }))}
        />
      </Field>
      <Field label="开始日期">
        <Input type="date" value={draft.date_from || ''} onChange={update('date_from')} />
      </Field>
      <Field label="结束日期">
        <Input type="date" value={draft.date_to || ''} onChange={update('date_to')} />
      </Field>
      <Field label="关键字">
        <Input
          placeholder="监测点名称 / 编码 / 标注说明"
          value={draft.keyword || ''}
          onChange={update('keyword')}
          onKeyDown={(event) => event.key === 'Enter' && onSubmit(draft)}
        />
      </Field>
    </FilterPanel>
  )
}
