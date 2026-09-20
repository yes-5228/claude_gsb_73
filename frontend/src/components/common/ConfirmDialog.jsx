import Modal from './Modal.jsx'

export default function ConfirmDialog({
  open,
  title = '操作确认',
  message,
  detail,
  confirmText = '确认',
  cancelText = '取消',
  danger = false,
  busy = false,
  onConfirm,
  onCancel
}) {
  return (
    <Modal
      open={open}
      title={title}
      onClose={onCancel}
      footer={
        <>
          <button type="button" className="btn" onClick={onCancel} disabled={busy}>
            {cancelText}
          </button>
          <button
            type="button"
            className={`btn ${danger ? 'btn-danger' : 'btn-primary'}`}
            onClick={onConfirm}
            disabled={busy}
          >
            {busy ? '处理中...' : confirmText}
          </button>
        </>
      }
    >
      <div className="stack">
        <div>{message}</div>
        {detail ? <div className="alert alert-warning">{detail}</div> : null}
      </div>
    </Modal>
  )
}
