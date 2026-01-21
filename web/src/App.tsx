import { Config, useConfig } from "./providers/config";
import { Translate } from "./providers/locale/Locale";
import { useEffect, useMemo, useRef, useState } from "react";
import { useNuiEvent } from "./providers/nui/useNui";
import { fetchNui } from "./providers/nui/fetchNui";
import { Button } from "./components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "./components/ui/dialog";

export function GetItemLabel({item} : {item: string}) {
  const { config } = useConfig();
  if (item == "money" || item == "dirty_money") {
    return <Translate id={item} />;
  }
  const itemLabel = config.items[item]?.label || config.items[item.toUpperCase()]?.label;
  if (!itemLabel) {
    return item;
  }
  return itemLabel;
}

export function GetItemImage(item: string) {
  const { config } = useConfig();
  return config.imageDirectory ? `${config.imageDirectory}/${item}.${config.imageExtension || "png"}` : `/nui/images/${item}.${config.imageExtension || "png"}`;
}

export function DisplayCurrency({value} : {value: number}) {
  const {config} = useConfig();
  return GetCurrencyString(value, config);
}

export function GetCurrencyString(value: number, config: Config) {
  return value.toLocaleString(config.countryCode || "en-US", {style: "currency", currency: config.currency || "USD", minimumFractionDigits: 0, maximumFractionDigits: 0});
}

type Business = {
  id: string;
  label: string;
  tier: number;
  unlockCost: number;
  feePercent: number;
  maxCapacity: number;
  cashPerSecond: number;
};

type Job = {
  id: string;
  businessId: string;
  amount: number;
  feePercent: number;
  startTs: number;
  endTs: number;
  status: string;
};

type ProcessorState = {
  serverTime: number;
  processorId: string;
  balances: { unprocessed: number; withdrawable: number };
  businesses: Business[];
  unlocked: Record<string, boolean>;
  activeCapacity: Record<string, number>;
  jobs: Job[];
  error?: string;
};

function clamp(v: number, min: number, max: number) {
  return Math.max(min, Math.min(max, v));
}

function formatDuration(seconds: number) {
  seconds = Math.max(0, Math.floor(seconds));
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function AppControls({controls} : {controls?: {key: string, label: any}[]}) {
    const controlsList = controls || [
        {key: "ESC", label: <Translate id="controls_exit" />},
    ];
    return (
        <div className="bg-background/95 p-2 absolute top-[20px] left-[20px] flex items-center gap-2 rounded-md">
            {controlsList.map((control, index) => (
                <div className="flex items-center justify-center gap-2" key={index}>
                    <div className="relative font-bold text-sm w-[28px] h-[28px] text-black rounded-md bg-white">
                        <div className="absolute top-[50%] left-[50%] z-1" style={{transform: "translate(-50%, -50%)"}}>
                            {control.key}
                        </div>
                    </div>
                    <div className="font-bold text-xl text-primary">{control.label}</div>
                </div>
            ))}
        </div>
    )
}

function App() {
  const { config } = useConfig();
  const [visible, setVisible] = useState(false);
  const [processorId, setProcessorId] = useState<string | null>(null);
  const [state, setState] = useState<ProcessorState | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [launderOpen, setLaunderOpen] = useState(false);
  const [launderBusinessId, setLaunderBusinessId] = useState<string | null>(null);
  const [launderStep, setLaunderStep] = useState<number>(10);

  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [withdrawStep, setWithdrawStep] = useState<number>(10);

  const refreshingRef = useRef<boolean>(false);
  const timeOffsetRef = useRef<number>(0); // fixed (serverNow - clientNow) in seconds
  const timeOffsetSetRef = useRef<boolean>(false);

  // Job cache so progress is estimated locally (start/end/current) and doesn't jump.
  const jobCacheRef = useRef<Record<string, Job>>({}); // [businessId] => job (last known)
  const serverJobsByBusinessIdRef = useRef<Record<string, boolean>>({}); // last server snapshot

  const clientNowSec = () => Date.now() / 1000;

  const applyServerTimeOnce = (serverTime: unknown) => {
    if (timeOffsetSetRef.current) return;
    const raw = Number(serverTime);
    if (!Number.isFinite(raw) || raw <= 0) return;
    // `serverTime` is second-resolution; +0.5 centers the second for smoother estimates.
    const serverNow = raw + 0.5;
    timeOffsetRef.current = serverNow - clientNowSec();
    timeOffsetSetRef.current = true;
  };

  const applyState = (res: ProcessorState) => {
    applyServerTimeOnce((res as any)?.serverTime);

    const nextServerJobs: Record<string, boolean> = {};
    for (const j of (res.jobs || [])) {
      nextServerJobs[j.businessId] = true;
      jobCacheRef.current[j.businessId] = j;
    }
    serverJobsByBusinessIdRef.current = nextServerJobs;
    setState(res);
  };

  const computedNow = () => {
    // Pure estimate: fixed offset + client clock (no re-sync), so progress stays smooth.
    return clientNowSec() + (timeOffsetRef.current || 0);
  };

  const refresh = async (pid?: string) => {
    const id = pid || processorId;
    if (!id) return;
    if (refreshingRef.current) return;
    refreshingRef.current = true;
    setError(null);
    try {
      const res = await fetchNui<ProcessorState>("pmw_processor_getState", { processorId: id });
      if ((res as any)?.error) {
        setError((res as any).error);
        return;
      }
      applyState(res);
    } catch (e: any) {
      setError(e?.message || "failed_to_fetch_state");
    } finally {
      refreshingRef.current = false;
    }
  };

  const close = async () => {
    setVisible(false);
    setProcessorId(null);
    setState(null);
    setError(null);
    timeOffsetRef.current = 0;
    timeOffsetSetRef.current = false;
    jobCacheRef.current = {};
    serverJobsByBusinessIdRef.current = {};
    setLaunderOpen(false);
    setLaunderBusinessId(null);
    setLaunderStep(10);
    setWithdrawOpen(false);
    setWithdrawStep(10);
    try {
      await fetchNui("pmw_close");
    } catch {}
  };

  useNuiEvent("pmw_open", (payload: any) => {
    const pid = payload?.processorId ? String(payload.processorId) : null;
    if (!pid) return;
    setProcessorId(pid);
    timeOffsetRef.current = 0;
    timeOffsetSetRef.current = false;
    jobCacheRef.current = {};
    serverJobsByBusinessIdRef.current = {};
    setLaunderOpen(false);
    setLaunderBusinessId(null);
    setLaunderStep(10);
    setWithdrawOpen(false);
    setWithdrawStep(10);
    setError(null);

    const initial = payload?.initialState;
    if (initial && !initial.error) {
      applyState(initial as ProcessorState);
      setVisible(true);
      return;
    }

    setState(null);
    setVisible(true);
    refresh(pid);
  });

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (!visible) return;
      if (e.key === "Escape") {
        e.preventDefault();
        close();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [visible]);

  // lightweight ticking so job timers/progress update without polling server
  const [, forceTick] = useState(0);
  useEffect(() => {
    if (!visible) return;
    const t = window.setInterval(() => forceTick((x) => (x + 1) % 1000000), 50);
    return () => window.clearInterval(t);
  }, [visible]);

  // Auto-refresh state while jobs are active so withdrawable updates on completion.
  useEffect(() => {
    if (!visible || !processorId) return;
    const hasJobs = (state?.jobs?.length || 0) > 0;
    const intervalMs = hasJobs ? 2500 : 10000;
    const t = window.setInterval(() => {
      void refresh(processorId);
    }, intervalMs);
    return () => window.clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, processorId, state?.jobs?.length]);

  const businesses = state?.businesses || [];
  const unlocked = state?.unlocked || {};
  const activeCapacity = state?.activeCapacity || {};
  const jobs = state?.jobs || [];

  const launderBusiness = launderBusinessId ? businesses.find((b) => b.id === launderBusinessId) : null;
  const launderCapMax = launderBusiness ? (launderBusiness.maxCapacity || 0) : 0;

  const jobByBusinessId = useMemo(() => {
    const map: Record<string, Job> = {};
    for (const j of jobs) {
      if (!map[j.businessId]) map[j.businessId] = j;
    }
    return map;
  }, [jobs]);

  const getDisplayJob = (businessId: string) => {
    const serverHasJob = !!jobByBusinessId[businessId];
    const cached = jobCacheRef.current[businessId];
    if (serverHasJob) return cached || jobByBusinessId[businessId];
    // If server no longer reports a job, keep showing cached job until it reaches 100%.
    if (!cached) return null;
    const now = computedNow();
    if (now >= (cached.endTs || 0)) {
      delete jobCacheRef.current[businessId];
      return null;
    }
    return cached;
  };

  const doUnlock = async (businessId: string) => {
    if (!processorId) return;
    setError(null);
    const res = await fetchNui<any>("pmw_processor_unlockBusiness", { processorId, businessId });
    if (res?.error) return setError(res.error);
    applyState(res);
  };

  const openLaunder = (businessId: string) => {
    setError(null);
    setLaunderBusinessId(businessId);
    setLaunderStep(10);
    setLaunderOpen(true);
  };

  const tenStepAmount = (step: number, min: number, max: number) => {
    step = Math.max(1, Math.min(10, Math.floor(step)));
    min = Math.max(1, Math.floor(min));
    max = Math.max(0, Math.floor(max));
    if (max <= 0) return 0;
    if (min > max) min = max;
    if (step === 10) return max;
    if (max === min) return max;
    const t = (step - 1) / 9;
    const v = Math.round(min + (max - min) * t);
    return Math.max(min, Math.min(max, v));
  };

  const doLaunder = async () => {
    if (!processorId || !launderBusinessId) return;
    const maxByUnprocessed = Math.floor(state?.balances?.unprocessed || 0);
    const capUsed = activeCapacity[launderBusinessId] || 0;
    const capMax = launderBusiness?.maxCapacity || 0;
    const maxByCapacity = capMax > 0 ? Math.max(0, capMax - capUsed) : maxByUnprocessed;
    const max = Math.max(0, Math.min(maxByUnprocessed, maxByCapacity));
    const min = Math.max(1, Math.ceil(max / 10));
    const amount = tenStepAmount(launderStep, min, max);
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("invalid_amount");
      return;
    }
    setError(null);
    const res = await fetchNui<any>("pmw_processor_deposit", { processorId, businessId: launderBusinessId, amount });
    if (res?.error) return setError(res.error);
    applyState(res);
    setLaunderStep(10);
    setLaunderOpen(false);
  };

  const doWithdraw = async (all?: boolean) => {
    if (!processorId) return;
    const max = Math.floor(state?.balances?.withdrawable || 0);
    const min = Math.max(1, Math.ceil(max / 10));
    const amount = all ? max : tenStepAmount(withdrawStep, min, max);
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("invalid_amount");
      return;
    }
    setError(null);
    const res = await fetchNui<any>("pmw_processor_withdraw", { processorId, amount });
    if (res?.error) return setError(res.error);
    applyState(res);
    setWithdrawStep(10);
    setWithdrawOpen(false);
  };

  const currency = (value: number) => GetCurrencyString(value || 0, config);

  if (!visible) {
    return <div className="dark w-screen h-screen absolute text-primary top-0 left-0 pointer-events-none" />;
  }

  return (
    <div className="dark w-screen h-screen absolute text-primary top-0 left-0">
      <AppControls />

      <div className="absolute inset-0 bg-black/50" onClick={close} />

      <div className="absolute inset-0 p-6 flex items-center justify-center">
        <div className="w-[1100px] max-w-[95vw] h-[700px] max-h-[92vh] bg-background/95 border border-border rounded-xl overflow-hidden shadow-2xl relative">
          <div className="px-5 py-4 border-b border-border flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold"><Translate id="pmw_title" /></div>
              <div className="text-sm text-muted-foreground">
                <span className="mr-3"><Translate id="pmw_unprocessed" />: <span className="font-semibold text-foreground">{currency(state?.balances?.unprocessed || 0)}</span></span>
                <span className="inline-flex items-center gap-2">
                  <span><Translate id="pmw_withdrawable" />: <span className="font-semibold text-foreground">{currency(state?.balances?.withdrawable || 0)}</span></span>
                  <Button
                    variant="secondary"
                    onClick={() => { setError(null); setWithdrawOpen(true); }}
                    disabled={(state?.balances?.withdrawable || 0) <= 0}
                  >
                    <Translate id="pmw_withdraw" />
                  </Button>
                </span>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="outline" onClick={close}><Translate id="controls_exit" /></Button>
            </div>
          </div>

          <div className="p-5 h-[calc(700px-72px)] max-h-[calc(92vh-72px)] overflow-auto">
            <div className="text-lg font-semibold mb-2"><Translate id="pmw_businesses" /></div>

            {(error || state?.error) && (
              <div className="mb-3 text-sm text-destructive">
                <Translate id={error || state?.error || "error"} />
              </div>
            )}

            <div className="space-y-2">
              {state && businesses.length === 0 && (
                <div className="text-muted-foreground"><Translate id="pmw_no_businesses" /></div>
              )}
              {businesses.map((b) => {
                const isUnlocked = !!unlocked[b.id];
                const capMax = b.maxCapacity || 0;

                const job = getDisplayJob(b.id);
                const start = job?.startTs || 0;
                const end = job?.endTs || 0;
                const now = computedNow();
                const dur = job ? Math.max(1, end - start) : 1;
                const prog = job ? clamp((now - start) / dur, 0, 1) : 0;
                const remaining = job ? Math.max(0, end - now) : 0;

                return (
                  <div key={b.id} className="border border-border rounded-lg p-3 bg-card/80">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <div className="text-base font-bold truncate">{b.label}</div>
                          <div className="text-xs text-muted-foreground">Tier {b.tier}</div>
                          {!isUnlocked && <div className="text-xs px-2 py-1 rounded bg-destructive/20 text-destructive"><Translate id="pmw_locked" /></div>}
                          {isUnlocked && <div className="text-xs px-2 py-1 rounded bg-emerald-500/20 text-emerald-400"><Translate id="pmw_unlocked" /></div>}
                          {job && <div className="text-xs px-2 py-1 rounded bg-primary/20 text-primary"><Translate id="pmw_processing" /></div>}
                        </div>

                        <div className="text-sm text-muted-foreground mt-1 flex flex-wrap gap-x-4 gap-y-1">
                          <div>
                            Max Capacity:{" "}
                            <span className="text-foreground font-semibold">
                              {capMax > 0 ? currency(capMax) : "Unlimited"}
                            </span>
                          </div>
                          <div>Fee: <span className="text-foreground font-semibold">{b.feePercent}%</span></div>
                          <div>Speed: <span className="text-foreground font-semibold">{Math.round((b.cashPerSecond || 0) * 100) / 100}</span> $/s</div>
                        </div>

                        {job && (
                          <div className="mt-3 border border-border rounded-md p-2 bg-background/60">
                            <div className="flex items-center justify-between">
                              <div className="text-sm font-semibold"><Translate id="pmw_job_in_progress" /></div>
                              <div className="text-xs text-muted-foreground">{formatDuration(remaining)} <Translate id="pmw_remaining" /></div>
                            </div>
                            <div className="text-xs text-muted-foreground mt-1">
                              <Translate id="pmw_amount" />: <span className="text-foreground font-semibold">{currency(job.amount)}</span> • Fee: {job.feePercent}%
                            </div>
                            <div className="mt-2 h-2 w-full bg-muted rounded overflow-hidden">
                              <div
                                className="h-full bg-primary transition-[width] duration-75 ease-linear"
                                style={{ width: `${prog * 100}%` }}
                              />
                            </div>
                          </div>
                        )}
                      </div>

                      <div className="flex flex-col gap-2 items-end">
                        {!isUnlocked ? (
                          <Button onClick={() => doUnlock(b.id)}>
                            <Translate id="pmw_unlock" /> {b.unlockCost > 0 ? `(${currency(b.unlockCost)})` : `(${config?.locale?.free || "Free"})`}
                          </Button>
                        ) : (
                          <Button variant="secondary" onClick={() => openLaunder(b.id)} disabled={!!job}>
                            <Translate id="pmw_launder_money" />
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>

      <Dialog
        open={launderOpen}
        onOpenChange={(open) => {
          setLaunderOpen(open);
          if (!open) {
            setLaunderBusinessId(null);
            setLaunderStep(10);
          }
        }}
      >
        <DialogContent className="sm:max-w-[520px]">
          <DialogHeader>
            <DialogTitle><Translate id="pmw_launder_money" /></DialogTitle>
            <DialogDescription>
              <Translate id="pmw_launder_desc" />
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            <div className="text-sm text-muted-foreground">
              <span className="mr-3"><Translate id="pmw_selected" />: <span className="text-foreground font-semibold">{launderBusiness?.label || "-"}</span></span>
            </div>
            {launderBusiness && (
              <div className="text-sm text-muted-foreground">
                Max Capacity:{" "}
                <span className="text-foreground font-semibold">
                  {launderCapMax > 0 ? currency(launderCapMax) : "Unlimited"}
                </span>
              </div>
            )}
            <div className="text-sm text-muted-foreground">
              <Translate id="pmw_unprocessed" />: <span className="text-foreground font-semibold">{currency(state?.balances?.unprocessed || 0)}</span>
            </div>
            {(() => {
              const maxByUnprocessed = Math.floor(state?.balances?.unprocessed || 0);
              const capUsed = launderBusinessId ? (activeCapacity[launderBusinessId] || 0) : 0;
              const capMax = launderBusiness?.maxCapacity || 0;
              const maxByCapacity = capMax > 0 ? Math.max(0, capMax - capUsed) : maxByUnprocessed;
              const max = Math.max(0, Math.min(maxByUnprocessed, maxByCapacity));
              const min = Math.max(1, Math.ceil(max / 10));
              const amount = tenStepAmount(launderStep, min, max);
              return (
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <div className="text-muted-foreground">{config?.locale?.exchange_amount || "Amount"}</div>
                    <div className="font-semibold text-foreground">{currency(amount)}</div>
                  </div>
                  <input
                    type="range"
                    min={1}
                    max={10}
                    step={1}
                    value={launderStep}
                    onChange={(e) => setLaunderStep(Number(e.target.value))}
                    className="w-full accent-primary"
                    disabled={max <= 0}
                  />
                  <div className="flex items-center justify-between">
                    <div className="text-xs text-muted-foreground">{currency(min)}</div>
                    <div className="text-xs text-muted-foreground">{currency(max)}</div>
                  </div>
                  <Button onClick={doLaunder} disabled={!launderBusinessId || max <= 0}>
                    <Translate id="pmw_confirm" />
                  </Button>
                </div>
              );
            })()}
            {(error || state?.error) && (
              <div className="text-sm text-destructive">
                <Translate id={error || state?.error || "error"} />
              </div>
            )}
          </div>

          <DialogFooter />
        </DialogContent>
      </Dialog>

      <Dialog
        open={withdrawOpen}
        onOpenChange={(open) => {
          setWithdrawOpen(open);
          if (!open) setWithdrawStep(10);
        }}
      >
        <DialogContent className="sm:max-w-[520px]">
          <DialogHeader>
            <DialogTitle><Translate id="pmw_withdraw" /></DialogTitle>
            <DialogDescription>
              <Translate id="pmw_withdraw_desc" />
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            <div className="text-sm text-muted-foreground">
              <Translate id="pmw_withdrawable" />: <span className="text-foreground font-semibold">{currency(state?.balances?.withdrawable || 0)}</span>
            </div>
            {(() => {
              const max = Math.floor(state?.balances?.withdrawable || 0);
              const min = Math.max(1, Math.ceil(max / 10));
              const amount = tenStepAmount(withdrawStep, min, max);
              return (
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <div className="text-muted-foreground">{config?.locale?.exchange_amount || "Amount"}</div>
                    <div className="font-semibold text-foreground">{currency(amount)}</div>
                  </div>
                  <input
                    type="range"
                    min={1}
                    max={10}
                    step={1}
                    value={withdrawStep}
                    onChange={(e) => setWithdrawStep(Number(e.target.value))}
                    className="w-full accent-primary"
                    disabled={max <= 0}
                  />
                  <div className="flex items-center justify-between">
                    <div className="text-xs text-muted-foreground">{currency(min)}</div>
                    <div className="text-xs text-muted-foreground">{currency(max)}</div>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button onClick={() => doWithdraw(false)} disabled={max <= 0}><Translate id="pmw_withdraw" /></Button>
                    <Button variant="secondary" onClick={() => doWithdraw(true)} disabled={max <= 0}><Translate id="pmw_all" /></Button>
                  </div>
                </div>
              );
            })()}
            {(error || state?.error) && (
              <div className="text-sm text-destructive">
                <Translate id={error || state?.error || "error"} />
              </div>
            )}
          </div>

          <DialogFooter />
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default App
