import { NavLink } from 'react-router-dom'
import { NAV_ITEMS } from '../../constants/index.js'

export default function SideNav() {
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="brand-logo">AQ</div>
        <div>
          <div className="brand-title">空气监测数据平台</div>
          <div className="brand-sub">Air Quality Data Entry</div>
        </div>
      </div>
      <nav className="nav">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
          >
            <span className="nav-icon">{item.icon}</span>
            <span>{item.label}</span>
          </NavLink>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div>GB 3095-2012 二级标准</div>
        <div>v1.0.0 · Flask + React</div>
      </div>
    </aside>
  )
}
