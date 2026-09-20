export function Field({ label, required, error, hint, children, className = '' }) {
  return (
    <div className={`field ${className}`}>
      {label ? (
        <label className="field-label">
          {label}
          {required ? <span className="req">*</span> : null}
        </label>
      ) : null}
      {children}
      {error ? <span className="field-error">{error}</span> : null}
      {!error && hint ? <span className="field-hint">{hint}</span> : null}
    </div>
  )
}

export function Input({ invalid, ...props }) {
  return <input className={`input ${invalid ? 'invalid' : ''}`} {...props} />
}

export function Select({ invalid, options = [], placeholder, ...props }) {
  return (
    <select className={`select ${invalid ? 'invalid' : ''}`} {...props}>
      {placeholder ? <option value="">{placeholder}</option> : null}
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  )
}

export function Textarea({ invalid, ...props }) {
  return <textarea className={`textarea ${invalid ? 'invalid' : ''}`} {...props} />
}

export function Checkbox({ label, ...props }) {
  return (
    <label className="checkbox">
      <input type="checkbox" {...props} />
      <span>{label}</span>
    </label>
  )
}
