export default function Tag({ tone = 'neutral', children, title }) {
  return (
    <span className={`tag tag-${tone}`} title={title}>
      {children}
    </span>
  )
}
