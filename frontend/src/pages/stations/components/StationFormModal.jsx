import { useEffect, useState } from 'react'
import Modal from '../../../components/common/Modal.jsx'
import { Checkbox, Field, Input, Select, Textarea } from '../../../components/common/FormField.jsx'
import { Alert } from '../../../components/common/Feedback.jsx'

const EMPTY = {
  code: '',
  name: '',
  area: '',
  address: '',
  station_type: 'ambient',
  status: 'active',
  longitude: '',
  latitude: '',
  installed_at: '',
  remark: ''
}

const TYPE_OPTIONS = [
  { value: 'ambient', label: '环境空气' },
  { value: 'traffic', label: '道路交通' },
  { value: 'background', label: '区域背景' },
  { value: 'industrial', label: '工业园区' },
  { value: 'rural', label: '农村站点' }
]

const STATUS_OPTIONS = [
  { value: 'active', label: '运行中' },
  { value: 'maintenance', label: '维护中' },
  { value: 'offline', label: '停用' }
]

function toForm(station) {
  if (!station) return { ...EMPTY }
  return {
    code: station.code ?? '',
    name: station.name ?? '',
    area: station.area ?? '',
    address: station.address ?? '',
    station_type: station.station_type ?? 'ambient',
    status: station.status ?? 'active',
    longitude: station.longitude ?? '',
    latitude: station.latitude ?? '',
    installed_at: station.installed_at ?? '',
    remark: station.remark ?? ''
  }
}

export default function StationFormModal({ open, station, areas = [], onClose, onSubmit }) {
  const [form, setForm] = useState(EMPTY)
  const [errors, setErrors] = useState({})
  const [message, setMessage] = useState(null)
  const [busy, setBusy] = useState(false)
  const [autoCode, setAutoCode] = useState(true)

  useEffect(() => {
    if (!open) return
    setForm(toForm(station))
    setErrors({})
    setMessage(null)
    setAutoCode(!station)
  }, [open, station])

  useEffect(() => {
    if (!open || !autoCode || station) return
    const stamp = new Date()
    const sequence = String(stamp.getMonth() + 1).padStart(2, '0') + String(stamp.getDate()).padStart(2, '0')
    setForm((prev) => (prev.code ? prev : { ...prev, code: `SZ-AQ-${sequence}` }))
  }, [open, autoCode, station])

  const set = (key) => (event) => {
    setForm({ ...form, [key]: event.target.value })
    setErrors((prev) => ({ ...prev, [key]: undefined }))
  }

  const submit = async (event) => {
    event.preventDefault()
    setBusy(true)
    setMessage(null)
    try {
      await onSubmit({
        ...form,
        longitude: form.longitude === '' ? null : Number(form.longitude),
        latitude: form.latitude === '' ? null : Number(form.latitude),
        installed_at: form.installed_at || null
      })
    } catch (error) {
      setErrors(error.fields || {})
      setMessage(error.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      open={open}
      wide
      title={station ? `编辑监测点 · ${station.code}` : '新增监测点'}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn" onClick={onClose} disabled={busy}>
            取消
          </button>
          <button type="submit" form="station-form" className="btn btn-primary" disabled={busy}>
            {busy ? '保存中...' : '保存'}
          </button>
        </>
      }
    >
      <form id="station-form" className="stack" onSubmit={submit}>
        {message ? <Alert tone="error">{message}</Alert> : null}
        <div className="form-grid">
          <Field label="监测点编码" required error={errors.code} hint="全局唯一, 建议使用 城市-类型-序号">
            <Input value={form.code} onChange={set('code')} invalid={Boolean(errors.code)} placeholder="SZ-AQ-009" />
          </Field>
          <Field label="监测点名称" required error={errors.name}>
            <Input value={form.name} onChange={set('name')} invalid={Boolean(errors.name)} placeholder="如: 市民中心站" />
          </Field>
          <Field label="所属区域" required error={errors.area}>
            <Input
              list="station-area-options"
              value={form.area}
              onChange={set('area')}
              invalid={Boolean(errors.area)}
              placeholder="如: 福田区"
            />
            <datalist id="station-area-options">
              {areas.map((area) => (
                <option key={area} value={area} />
              ))}
            </datalist>
          </Field>
          <Field label="详细地址" error={errors.address}>
            <Input value={form.address} onChange={set('address')} placeholder="道路 + 门牌" />
          </Field>
          <Field label="监测点类型" required error={errors.station_type}>
            <Select value={form.station_type} onChange={set('station_type')} options={TYPE_OPTIONS} />
          </Field>
          <Field label="运行状态" required error={errors.status}>
            <Select value={form.status} onChange={set('status')} options={STATUS_OPTIONS} />
          </Field>
          <Field label="经度" error={errors.longitude} hint="-180 ~ 180">
            <Input type="number" step="0.0001" value={form.longitude} onChange={set('longitude')} invalid={Boolean(errors.longitude)} />
          </Field>
          <Field label="纬度" error={errors.latitude} hint="-90 ~ 90">
            <Input type="number" step="0.0001" value={form.latitude} onChange={set('latitude')} invalid={Boolean(errors.latitude)} />
          </Field>
          <Field label="投运日期" error={errors.installed_at}>
            <Input type="date" value={form.installed_at} onChange={set('installed_at')} />
          </Field>
          <Field label="备注" error={errors.remark} className="span-2">
            <Textarea value={form.remark} onChange={set('remark')} placeholder="点位周边环境、运维说明等" />
          </Field>
        </div>
        {!station ? (
          <Checkbox
            label="自动生成建议编码"
            checked={autoCode}
            onChange={(event) => setAutoCode(event.target.checked)}
          />
        ) : null}
      </form>
    </Modal>
  )
}
