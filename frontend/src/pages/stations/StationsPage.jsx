import { useCallback, useState } from 'react'
import { createStation, deleteStation, listStations, updateStation } from '../../api/stations.js'
import ConfirmDialog from '../../components/common/ConfirmDialog.jsx'
import Pagination from '../../components/common/Pagination.jsx'
import { SectionCard } from '../../components/common/Card.jsx'
import { Alert } from '../../components/common/Feedback.jsx'
import { useToast } from '../../components/common/ToastProvider.jsx'
import { useListQuery } from '../../hooks/useListQuery.js'
import { resetOptionCache } from '../../hooks/useOptions.js'
import StationDetailDrawer from './components/StationDetailDrawer.jsx'
import StationFilters from './components/StationFilters.jsx'
import StationFormModal from './components/StationFormModal.jsx'
import StationTable from './components/StationTable.jsx'

const INITIAL_FILTERS = { keyword: '', area: '', status: '', station_type: '' }

export default function StationsPage() {
  const toast = useToast()
  const query = useListQuery(listStations, INITIAL_FILTERS)
  const [formState, setFormState] = useState({ open: false, station: null })
  const [detailId, setDetailId] = useState(null)
  const [pendingDelete, setPendingDelete] = useState(null)
  const [deleting, setDeleting] = useState(false)

  const { reload } = query
  const areas = query.data?.areas ?? []

  const handleSubmit = useCallback(
    async (payload) => {
      if (formState.station) {
        await updateStation(formState.station.id, payload)
        toast.success(`监测点 ${payload.code} 已更新`)
      } else {
        await createStation(payload)
        toast.success(`监测点 ${payload.code} 已创建`)
      }
      setFormState({ open: false, station: null })
      resetOptionCache() // 台账变更后刷新下拉选项缓存
      reload()
    },
    [formState.station, reload, toast]
  )

  const handleDelete = useCallback(async () => {
    if (!pendingDelete) return
    setDeleting(true)
    try {
      const result = await deleteStation(pendingDelete.id)
      toast.success(
        `已删除 ${pendingDelete.code}, 同时清理监测数据 ${result.removed.measurements_removed} 条、超标记录 ${result.removed.exceedances_removed} 条`
      )
      setPendingDelete(null)
      resetOptionCache()
      reload()
    } catch (error) {
      toast.error(error.message)
    } finally {
      setDeleting(false)
    }
  }, [pendingDelete, reload, toast])

  return (
    <>
      <StationFilters
        value={query.filters}
        areas={areas}
        loading={query.loading}
        onSubmit={(next) => query.setFilters(next)}
        onReset={() => query.setFilters(INITIAL_FILTERS)}
      />

      {query.error ? <Alert tone="error">{query.error.message}</Alert> : null}

      <SectionCard
        title="监测点清单"
        hint="台账信息用于数据录入与超标记录的归属追溯"
        actions={
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => setFormState({ open: true, station: null })}
          >
            + 新增监测点
          </button>
        }
      >
        <StationTable
          rows={query.items}
          loading={query.loading}
          onDetail={(row) => setDetailId(row.id)}
          onEdit={(row) => setFormState({ open: true, station: row })}
          onDelete={(row) => setPendingDelete(row)}
        />
        <Pagination
          page={query.page}
          pages={query.pages}
          total={query.total}
          pageSize={query.pageSize}
          onPageChange={query.setPage}
          onPageSizeChange={query.setPageSize}
        />
      </SectionCard>

      <StationFormModal
        open={formState.open}
        station={formState.station}
        areas={areas}
        onClose={() => setFormState({ open: false, station: null })}
        onSubmit={handleSubmit}
      />

      <StationDetailDrawer
        stationId={detailId}
        onClose={() => setDetailId(null)}
        onEdit={(station) => {
          setDetailId(null)
          setFormState({ open: true, station })
        }}
      />

      <ConfirmDialog
        open={Boolean(pendingDelete)}
        danger
        busy={deleting}
        title="删除监测点"
        message={`确认删除监测点「${pendingDelete?.name || ''}」吗?`}
        detail="删除后该监测点下的监测数据与超标记录将一并移除, 该操作不可恢复。"
        confirmText="确认删除"
        onConfirm={handleDelete}
        onCancel={() => setPendingDelete(null)}
      />
    </>
  )
}
