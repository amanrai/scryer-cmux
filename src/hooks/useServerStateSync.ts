import { useEffect, type MutableRefObject } from 'react';
import { API_BASE } from '../constants';
import type { AppState, WorkspaceModel } from '../types';

type StateStatus = 'loading' | 'synced' | 'offline';

type UseServerStateSyncArgs = {
  workspaces: WorkspaceModel[];
  activeWorkspaceId: string;
  loadedRef: MutableRefObject<boolean>;
  setWorkspaces: (workspaces: WorkspaceModel[]) => void;
  setActiveWorkspaceId: (workspaceId: string) => void;
  setHostName: (hostName: string) => void;
  setStateStatus: (status: StateStatus) => void;
};

export function useServerStateSync({
  workspaces,
  activeWorkspaceId,
  loadedRef,
  setWorkspaces,
  setActiveWorkspaceId,
  setHostName,
  setStateStatus,
}: UseServerStateSyncArgs) {
  useEffect(() => {
    let cancelled = false;
    fetch(`${API_BASE}/api/state`)
      .then((response) => {
        if (!response.ok) throw new Error(`state load failed: ${response.status}`);
        return response.json() as Promise<AppState>;
      })
      .then((state) => {
        if (cancelled) return;
        setWorkspaces(state.workspaces);
        setActiveWorkspaceId(state.activeWorkspaceId);
        if (state.hostName) setHostName(state.hostName);
        loadedRef.current = true;
        setStateStatus('synced');
      })
      .catch(() => {
        if (cancelled) return;
        loadedRef.current = true;
        setStateStatus('offline');
      });
    return () => { cancelled = true; };
  }, [loadedRef, setActiveWorkspaceId, setHostName, setStateStatus, setWorkspaces]);

  useEffect(() => {
    if (!loadedRef.current) return;
    fetch(`${API_BASE}/api/state`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ workspaces, activeWorkspaceId }),
      keepalive: true,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`state save failed: ${response.status}`);
        return response.json() as Promise<AppState>;
      })
      .then((state) => {
        if (state.hostName) setHostName(state.hostName);
        setStateStatus('synced');
      })
      .catch(() => setStateStatus('offline'));
  }, [activeWorkspaceId, loadedRef, setHostName, setStateStatus, workspaces]);

  useEffect(() => {
    function flushState() {
      if (!loadedRef.current) return;
      const payload = JSON.stringify({ workspaces, activeWorkspaceId });
      if (navigator.sendBeacon) {
        navigator.sendBeacon(`${API_BASE}/api/state`, new Blob([payload], { type: 'application/json' }));
        return;
      }
      fetch(`${API_BASE}/api/state`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: payload, keepalive: true }).catch(() => {});
    }

    window.addEventListener('pagehide', flushState);
    return () => window.removeEventListener('pagehide', flushState);
  }, [activeWorkspaceId, loadedRef, workspaces]);
}
