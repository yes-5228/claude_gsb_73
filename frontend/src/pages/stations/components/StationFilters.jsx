import { useEffect, useState } from 'react'
import { FilterPanel } from '../../../components/common/Card.jsx'
import { Field, Input, Select } from '../../../components/common/FormField.jsx'

const STATUS_OPTIONS = [
  { value: 'active', label: '运行中' },
  { value: 'maintenance', label: '维护中' },
  { value: 'offline', label: '停用' }
]

const TYPE_OPTIONS = [
  { value: 'ambient', label: '环境空气' },
  { value: 'traffic', label: '道路交通' },
  { value: 'background', label: '区域背景' },
  { value: 'industrial', label: '工业园区' },
  { value: 'rural', label: '农村站点' }
]

export default function StationFilters({ value, areas = [], loading, onSubmit, onReset }) {
  const [draft, setDraft] = useState(value)

  useEffect(() => {
    setDraft(value)
  }, [value])

  const update = (key) => (event) => setDraft({ ...draft, [key]: event.target.value })

  return (
    <FilterPanel
      loading={loading}
      onSearch={() => onSubmit(draft)}
      onReset={() => {
        setDraft({ keyword: '', area: '', status: '', station_type: '' })
        onReset()
      }}
    >
      <Field label="关键字">
        <Input
          placeholder="监测点名称 / 编码 / 地址"
          value={draft.keyword || ''}
          onChange={update('keyword')}
          onKeyDown={(event) => event.key === 'Enter' && onSubmit(draft)}
        />
      </Field>
      <Field label="所属区域">
        <Select
          value={draft.area || ''}
          onChange={update('area')}
          placeholder="全部区域"
          options={areas.map((area) => ({ value: area, label: area }))}
        />
      </Field>
      <Field label="监测点类型">
        <Select value={draft.station_type || ''} onChange={update('station_type')} placeholder="全部类型" options={TYPE_OPTIONS} />
      </Field>
      <Field label="运行状态">
        <Select value={draft.status || ''} onChange={update('status')} placeholder="全部状态" options={STATUS_OPTIONS} />
      </Field>
    </FilterPanel>
  )
}
