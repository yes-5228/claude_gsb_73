import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import AppLayout from './components/layout/AppLayout.jsx'
import { ToastProvider } from './components/common/ToastProvider.jsx'
import OverviewPage from './pages/overview/OverviewPage.jsx'
import StationsPage from './pages/stations/StationsPage.jsx'
import MeasurementsPage from './pages/measurements/MeasurementsPage.jsx'
import ExceedancesPage from './pages/exceedances/ExceedancesPage.jsx'
import QueryPage from './pages/query/QueryPage.jsx'

export default function App() {
  return (
    <ToastProvider>
      <BrowserRouter>
        <AppLayout>
          <Routes>
            <Route path="/" element={<Navigate to="/overview" replace />} />
            <Route path="/overview" element={<OverviewPage />} />
            <Route path="/stations" element={<StationsPage />} />
            <Route path="/measurements" element={<MeasurementsPage />} />
            <Route path="/exceedances" element={<ExceedancesPage />} />
            <Route path="/query" element={<QueryPage />} />
            <Route path="*" element={<Navigate to="/overview" replace />} />
          </Routes>
        </AppLayout>
      </BrowserRouter>
    </ToastProvider>
  )
}
