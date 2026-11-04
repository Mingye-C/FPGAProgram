cd [file dirname [info script]]
set phy ./src/td_project/UPLoad2_Runs/phy_1
set fd [open $phy/.elevator_build_started r];set started [string trim [read $fd]];close $fd
proc require_fresh {path started} {
 if {![file exists $path] || [file mtime $path] < $started} {error "Missing/stale: $path"}
}
if {[catch {
 set syn ./src/td_project/UPLoad2_Runs/syn_1
 require_fresh $syn/.opt_gate.end.f $started
 require_fresh $syn/UPLoad2_gate.db $started
 import_device eagle_s20.db -package EG4S20BG256
 open_project ./src/td_project/UPLoad2.al -single_run
 load_run_param -run phy_1
 import_db $syn/UPLoad2_gate.db
 commit_param -step place
 set_param flow thread 1
 set_param place hfn_opt_effort low
    set_param place seed 7
 place
 update_timing -mode manhattan
 report_timing_summary -file $phy/UPLoad2_place.timing
 report_timing_status -file $phy/UPLoad2_place.ts
 flow_status -file $phy/place_flow.status
 export_db $phy/UPLoad2_place.db
 puts ELEVATOR_PLACE_RETURNED
 commit_param -step route
 set_param flow thread 1
 set_param route effort routability
 set_param route fix_hold off
 route
 puts ELEVATOR_ROUTE_RETURNED
 set_param route fix_hold high
 fix_hold
 fix_hold
 puts ELEVATOR_HOLD_REPAIR_RETURNED
 set_param route fix_hold on
 drc_check -route
 report_route_status -drc -file $phy/elevator_route_status.rpt
 update_timing -mode final
 report_area -io_info -file $phy/UPLoad2_phy.area
 report_timing_status -file $phy/UPLoad2_phy.ts
 report_timing_summary -file $phy/UPLoad2_pr.timing
 report_timing_exception -file $phy/UPLoad2_exception.timing
 check_timing -verbose -file $phy/UPLoad2_chk.timing
 flow_status -file $phy/route_flow.status
 set fd [open $phy/UPLoad2_pr.timing r];set report [read $fd];close $fd
 if {![regexp {SWNS: *([-0-9.]+)ns, STNS: *([-0-9.]+)ns} $report all sw st] ||
     ![regexp {HWNS: *([-0-9.]+)ns, HTNS: *([-0-9.]+)ns} $report all hw ht]} {error "Final timing not parseable"}
 if {$sw<0 || $st<0 || $hw<0 || $ht<0} {error "Final setup/hold failed: $sw/$hw"}
 export_db $phy/UPLoad2_pr.db
 commit_param -step bitgen
 bitgen -bit $phy/UPLoad2.bit
 export_bitgen_param -file $phy/.bitgen_param.f
 require_fresh $phy/UPLoad2.bit $started
 set fd [open $phy/.elevator_impl.end.f w];puts $fd "route + standalone fix_hold + final STA + bitgen PASS";close $fd
 puts "ELEVATOR_IMPL_PASS Setup=$sw Hold=$hw"
} msg]} {puts stderr "ELEVATOR_IMPL_FAIL: $msg";exit 1}
exit 0

