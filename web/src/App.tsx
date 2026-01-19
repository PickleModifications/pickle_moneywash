import { Config, useConfig } from "./providers/config";
import { Translate } from "./providers/locale/Locale";
import { useEffect, useMemo, useRef, useState } from "react";
import { useNuiEvent } from "./providers/nui/useNui";
import { fetchNui } from "./providers/nui/fetchNui";
import { Button } from "./components/ui/button";

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
  secondsPerCash: number;
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
  balances: { counted: number; withdrawable: number };
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

  const [depositBusinessId, setDepositBusinessId] = useState<string | null>(null);
  const [depositAmount, setDepositAmount] = useState<string>("");
  const [withdrawAmount, setWithdrawAmount] = useState<string>("");

  const receivedAtMsRef = useRef<number>(Date.now());
  const serverTimeRef = useRef<number>(0);

  const computedNow = () => {
    const recvAt = receivedAtMsRef.current || Date.now();
    const serverAt = serverTimeRef.current || 0;
    const delta = (Date.now() - recvAt) / 1000;
    return serverAt + delta;
  };

  const refresh = async (pid?: string) => {
    const id = pid || processorId;
    if (!id) return;
    setError(null);
    try {
      const res = await fetchNui<ProcessorState>("pmw_processor_getState", { processorId: id });
      if ((res as any)?.error) {
        setError((res as any).error);
        return;
      }
      receivedAtMsRef.current = Date.now();
      serverTimeRef.current = res.serverTime || Math.floor(Date.now() / 1000);
      setState(res);
    } catch (e: any) {
      setError(e?.message || "failed_to_fetch_state");
    }
  };

  const close = async () => {
    setVisible(false);
    setProcessorId(null);
    setState(null);
    setError(null);
    try {
      await fetchNui("pmw_close");
    } catch {}
  };

  useNuiEvent("pmw_open", (payload: any) => {
    const pid = payload?.processorId ? String(payload.processorId) : null;
    if (!pid) return;
    setProcessorId(pid);
    setVisible(true);
    setDepositBusinessId(null);
    setDepositAmount("");
    setWithdrawAmount("");
    setState(null);
    setError(null);
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
    const t = window.setInterval(() => forceTick((x) => (x + 1) % 1000000), 500);
    return () => window.clearInterval(t);
  }, [visible]);

  const businesses = state?.businesses || [];
  const unlocked = state?.unlocked || {};
  const activeCapacity = state?.activeCapacity || {};
  const jobs = state?.jobs || [];

  const depositBusiness = depositBusinessId ? businesses.find((b) => b.id === depositBusinessId) : null;
  const depositCapUsed = depositBusiness ? (activeCapacity[depositBusiness.id] || 0) : 0;
  const depositCapMax = depositBusiness ? (depositBusiness.maxCapacity || 0) : 0;

  const doUnlock = async (businessId: string) => {
    if (!processorId) return;
    setError(null);
    const res = await fetchNui<any>("pmw_processor_unlockBusiness", { processorId, businessId });
    if (res?.error) return setError(res.error);
    receivedAtMsRef.current = Date.now();
    serverTimeRef.current = res.serverTime || Math.floor(Date.now() / 1000);
    setState(res);
  };

  const doDeposit = async () => {
    if (!processorId || !depositBusinessId) return;
    const amount = Math.floor(Number(depositAmount));
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("invalid_amount");
      return;
    }
    setError(null);
    const res = await fetchNui<any>("pmw_processor_deposit", { processorId, businessId: depositBusinessId, amount });
    if (res?.error) return setError(res.error);
    receivedAtMsRef.current = Date.now();
    serverTimeRef.current = res.serverTime || Math.floor(Date.now() / 1000);
    setState(res);
    setDepositAmount("");
  };

  const doWithdraw = async (all?: boolean) => {
    if (!processorId) return;
    const amount = all ? (state?.balances?.withdrawable || 0) : Math.floor(Number(withdrawAmount));
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("invalid_amount");
      return;
    }
    setError(null);
    const res = await fetchNui<any>("pmw_processor_withdraw", { processorId, amount });
    if (res?.error) return setError(res.error);
    receivedAtMsRef.current = Date.now();
    serverTimeRef.current = res.serverTime || Math.floor(Date.now() / 1000);
    setState(res);
    setWithdrawAmount("");
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
              <div className="text-2xl font-bold">Money Wash</div>
              <div className="text-sm text-muted-foreground">
                <span className="mr-3">Counted: <span className="font-semibold text-foreground">{currency(state?.balances?.counted || 0)}</span></span>
                <span>Withdrawable: <span className="font-semibold text-foreground">{currency(state?.balances?.withdrawable || 0)}</span></span>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="secondary" onClick={() => refresh()}>Refresh</Button>
              <Button variant="outline" onClick={close}><Translate id="controls_exit" /></Button>
            </div>
          </div>

          <div className="p-5 grid grid-cols-12 gap-4 h-[calc(700px-72px)] max-h-[calc(92vh-72px)]">
            <div className="col-span-7 h-full overflow-auto pr-1">
              <div className="text-lg font-semibold mb-2">Businesses</div>
              <div className="space-y-2">
                {businesses.length === 0 && (
                  <div className="text-muted-foreground">No businesses configured.</div>
                )}
                {businesses.map((b) => {
                  const isUnlocked = !!unlocked[b.id];
                  const capUsed = activeCapacity[b.id] || 0;
                  const capMax = b.maxCapacity || 0;
                  const capPct = capMax > 0 ? clamp(capUsed / capMax, 0, 1) : 0;
                  return (
                    <div key={b.id} className="border border-border rounded-lg p-3 bg-card/80">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <div className="text-base font-bold truncate">{b.label}</div>
                            <div className="text-xs text-muted-foreground">Tier {b.tier}</div>
                            {!isUnlocked && <div className="text-xs px-2 py-1 rounded bg-destructive/20 text-destructive">Locked</div>}
                            {isUnlocked && <div className="text-xs px-2 py-1 rounded bg-emerald-500/20 text-emerald-400">Unlocked</div>}
                          </div>
                          <div className="text-sm text-muted-foreground mt-1 grid grid-cols-2 gap-x-4 gap-y-1">
                            <div>Fee: <span className="text-foreground font-semibold">{b.feePercent}%</span></div>
                            <div>Speed: <span className="text-foreground font-semibold">{b.secondsPerCash}s</span> per $1</div>
                            <div>Capacity: <span className="text-foreground font-semibold">{currency(capUsed)}</span> / {currency(capMax)}</div>
                            <div>
                              Remaining:{" "}
                              <span className="text-foreground font-semibold">
                                {capMax > 0 ? currency(Math.max(0, capMax - capUsed)) : "Unlimited"}
                              </span>
                            </div>
                          </div>

                          {capMax > 0 && (
                            <div className="mt-2 h-2 w-full bg-muted rounded overflow-hidden">
                              <div className="h-full bg-primary" style={{ width: `${capPct * 100}%` }} />
                            </div>
                          )}
                        </div>

                        <div className="flex flex-col gap-2 items-end">
                          {!isUnlocked ? (
                            <Button
                              onClick={() => doUnlock(b.id)}
                            >
                              Unlock {b.unlockCost > 0 ? `(${currency(b.unlockCost)})` : "(Free)"}
                            </Button>
                          ) : (
                            <Button variant="secondary" onClick={() => setDepositBusinessId(b.id)}>
                              Deposit
                            </Button>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="col-span-5 h-full overflow-auto pl-1">
              <div className="text-lg font-semibold mb-2">Processing</div>

              <div className="border border-border rounded-lg p-3 bg-card/80 mb-4">
                <div className="font-semibold mb-2">Deposit counted money</div>
                <div className="text-sm text-muted-foreground mb-2">
                  Selected: <span className="text-foreground font-semibold">{depositBusiness?.label || "None"}</span>
                </div>
                {depositBusiness && (
                  <div className="text-sm text-muted-foreground mb-2">
                    Capacity: <span className="text-foreground font-semibold">{currency(depositCapUsed)}</span> / {currency(depositCapMax)}
                  </div>
                )}
                <div className="flex items-center gap-2">
                  <input
                    className="flex-1 bg-background border border-input rounded-md px-3 h-9 text-sm"
                    placeholder="Amount"
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                  />
                  <Button onClick={doDeposit} disabled={!depositBusinessId}>Start</Button>
                </div>
              </div>

              <div className="border border-border rounded-lg p-3 bg-card/80 mb-4">
                <div className="font-semibold mb-2">Withdraw washed cash</div>
                <div className="flex items-center gap-2">
                  <input
                    className="flex-1 bg-background border border-input rounded-md px-3 h-9 text-sm"
                    placeholder="Amount"
                    value={withdrawAmount}
                    onChange={(e) => setWithdrawAmount(e.target.value)}
                  />
                  <Button onClick={() => doWithdraw(false)}>Withdraw</Button>
                  <Button variant="secondary" onClick={() => doWithdraw(true)}>All</Button>
                </div>
              </div>

              <div className="border border-border rounded-lg p-3 bg-card/80">
                <div className="font-semibold mb-2">Active jobs</div>
                {jobs.length === 0 && (
                  <div className="text-sm text-muted-foreground">No active jobs.</div>
                )}
                <div className="space-y-2 max-h-[280px] overflow-auto pr-1">
                  {jobs.map((j) => {
                    const b = businesses.find((x) => x.id === j.businessId);
                    const start = j.startTs || 0;
                    const end = j.endTs || 0;
                    const now = computedNow();
                    const dur = Math.max(1, end - start);
                    const prog = clamp((now - start) / dur, 0, 1);
                    const remaining = Math.max(0, end - now);
                    return (
                      <div key={j.id} className="border border-border rounded-md p-2 bg-background/70">
                        <div className="flex items-center justify-between">
                          <div className="text-sm font-semibold">{b?.label || j.businessId}</div>
                          <div className="text-xs text-muted-foreground">{formatDuration(remaining)} remaining</div>
                        </div>
                        <div className="text-xs text-muted-foreground mt-1">
                          Amount: <span className="text-foreground font-semibold">{currency(j.amount)}</span> • Fee: {j.feePercent}%
                        </div>
                        <div className="mt-2 h-2 w-full bg-muted rounded overflow-hidden">
                          <div className="h-full bg-primary" style={{ width: `${prog * 100}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {(error || state?.error) && (
                <div className="mt-3 text-sm text-destructive">
                  Error: {error || state?.error}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default App
