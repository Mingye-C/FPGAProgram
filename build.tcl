cd [file dirname [info script]]
set project_file ./src/td_project/UPLoad2.al
set f [open $project_file r];set project_xml [read $f];close $f
regsub {Path="[^"]*"} $project_xml [format {Path="%s"} [file normalize ./src/td_project]] project_xml
set f [open $project_file w];puts -nonewline $f $project_xml;close $f
set started [clock seconds]
set runs ./src/td_project/UPLoad2_Runs
proc require_fresh {path started} {
    if {![file exists $path] || [file mtime $path] < $started} {
        error "Missing or stale build artifact: $path"
    }
}
if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    open_project ./src/td_project/UPLoad2.al
    top_module top
    set_param flow thread 1 -run phy_1
    set_param place pr_strategy 5 -run phy_1
    set_param place hfn_opt_effort low -run phy_1
    set_param place seed 2 -run phy_1
    set_param gate pack_effort high -run syn_1
    reset_runs syn_1 -f
    launch_runs syn_1 -step gate -jobs 1
    if {[catch {wait_run syn_1} msg]} {puts "TD wait_run diagnostic: $msg"}
    require_fresh $runs/syn_1/.opt_gate.end.f $started
    require_fresh $runs/syn_1/UPLoad2_gate.db $started
    file mkdir $runs/phy_1
    set fd [open $runs/phy_1/.elevator_build_started w];puts $fd $started;close $fd
    exec [info nameofexecutable] [file join [pwd] build_elevator_impl.tcl] >@ stdout 2>@ stderr
    require_fresh $runs/phy_1/.elevator_impl.end.f $started
    set bit $runs/phy_1/UPLoad2.bit
    set timing $runs/phy_1/UPLoad2_pr.timing
    require_fresh $bit $started
    require_fresh $timing $started
    set fd [open $timing r]; set report [read $fd]; close $fd
    if {![regexp {SWNS: *([-0-9.]+)ns, STNS: *([-0-9.]+)ns} $report all swns stns] ||
        ![regexp {HWNS: *([-0-9.]+)ns, HTNS: *([-0-9.]+)ns} $report all hwns htns]} {
        error "Could not parse timing report"
    }
    if {$swns < 0 || $hwns < 0 || $stns < 0 || $htns < 0} {error "Timing failed: $swns / $hwns"}
    file copy -force $bit ./UPLoad2.bit
    puts "MEDIA_V1_BUILD_PASS Setup=$swns Hold=$hwns bit=$bit"
} failure]} {
    puts stderr "MEDIA_V1_BUILD_FAIL: $failure"
    exit 1
}
exit 0

