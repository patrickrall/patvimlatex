"
" PatVimLatex
" Integrates llpp with latex editing in vim
" Adapted from Keven C. Klement's live-latex-preview
"

function! PVLInitGlobals()
    " prefix
    let b:msgprefix = "[PatVimLatex] "

    " Get file position
    let b:texfile = expand("%:p")
    let b:texfilename = substitute(expand("%:t"), '\.tex$', "", "")

    " Make temporary folder
    let b:apptmp = $HOME . "/.cache/patvimlatex/" 
    let b:tmpdir = $HOME . "/.cache/patvimlatex/" . substitute(substitute(expand("%:p"), "/", "", "g"),"\.tex$", "", "" )

    " Window id variables
    " 999999 means unset
    let b:windowid = "999999"
    let b:viewerpid = "999999"
    
    " options
    if !exists("g:PVLReferenceWarningPrompt")
        let g:PVLReferenceWarningPrompt = 1
    end
endfunction


" Logging functions
function! PVLMessage(message)
    echohl Normal | unsilent echo b:msgprefix . a:message
endfunction

function! PVLErrorMessage(message)
    echohl ErrorMsg | unsilent echo b:msgprefix . a:message
    echohl Normal
endfunction

" File functions
function! PVLLogFile()
    return  b:tmpdir . "/" . b:texfilename . ".log"
endfunction

function! PVLPdfFile()
    return b:tmpdir . "/" . b:texfilename . ".pdf"
endfunction


" Compile PDF
function! PVLCompilePDF()
    " Clear tmpdir of log and pdf files
    " Important! Do not clear aux file, otherwise references will never work.
    if !isdirectory(b:tmpdir)
        silent! call system("mkdir -p \"" . b:tmpdir . "\"")
    endif
    
    if filereadable(PVLPdfFile())
        silent! call system("rm \"" . PVLPdfFile() . "\"")
    endif

    if filereadable(PVLLogFile())
        silent! call system("rm \"" . PVLLogFile() . "\"")
    endif
    

    " Assemble pdflatex compile command
    let compilecommand = "pdflatex -interaction=nonstopmode"
    let compilecommand = compilecommand . " -stop-on-error"
    let compilecommand = compilecommand . " -file-line-error -synctex=1"
    let compilecommand = compilecommand . " -output-directory=\'" . b:tmpdir . "\'"
    let compilecommand = compilecommand . " \'" . b:texfile . "\'"
    let compilecommand = compilecommand . " >> " . b:apptmp . "texoutput.log"

    " Write executed command to safety log file
    silent! call system("echo \"" . compilecommand . "\" > " . b:apptmp . "texoutput.log")

    " Execute compile command
    silent! call system(compilecommand)

    " Verify if log output was generated
    " This fails very rarely, for instance when a bogus input file is given
    " or when a system update breaks tex completely
    if !filereadable(PVLLogFile())
        " If not, ask user
        call PVLErrorMessage("pdflatex generated no log file")
        let viewfile = confirm(b:msgprefix . "View pdflatex output? ", "&Y\n&\N", 2)
        if viewfile == 1
            exec ":sp " . b:apptmp . "texoutput.log"
        endif
        
        " Return failure
        return 0
    endif

    " Verify if pdf output was generated
    if !filereadable(PVLPdfFile())
        call PVLErrorMessage("pdflatex generated no pdf file")
        call PVLCountErrorsAndWarnings()
        return 0
    endif

    if !PVLCheckCrossreferencesWarning()
        call PVLCountErrorsAndWarnings("quiet")
    endif
    return 1
endfunction

" Export function to current directory
function! PVLExportPDF()
   if filereadable(PVLPdfFile())
        silent! call system("cp \"" . PVLPdfFile() . "\" \"" . expand("%:h") . "\"")
        call PVLMessage("Exported pdf to " . expand("%:p:h") . "/" . b:texfilename . ".pdf")
    else
        call PVLErrorMessage("No pdf file to export")
    endif
endfunction

function! PVLPrint()
   if filereadable(PVLPdfFile())
        call inputsave()
        :let cmd = input("Edit print command: ","lp " . PVLPdfFile())
        call inputrestore()
        silent! call system(cmd)
        echo "\n"
        call PVLMessage("Print command executed.")
    else
        call PVLErrorMessage("No pdf file to print")
    endif
endfunction


" Error handling functions
function! PVLCountErrorsAndWarnings(...)
    let errors = system("cat \"" . PVLLogFile() . "\" | grep \".tex:\" | wc -l | tr -d '\n'")
     
    let errmessages = system("cat \"" . PVLLogFile() . "\" | grep \"\^\!\" | wc -l | tr -d '\n' ")
    
    let warnings = system("cat \"" . PVLLogFile() . "\" | grep \"LaTeX Warning:\" | "
                \. " wc -l | tr -d '\n' ")

    " compute english
    let errorsplural = "s"
    let errmessagesplural = "s"
    let warningsplural = "s"
    if errors == "1" 
        let errorsplural = ""
    endif
    if errmessages == "1" 
        let errmessagesplural = ""
    endif
    if warnings == "1"
        let warningsplural = "" 
    endif

    if errors == "0" && warnings == "0" && errmessages == "0"
        " if we have no quiet argument, display message of no errors
        if a:0 == 0
             call PVLMessage("Found no line errors, error messages or warnings in log file")
        endif
    else
        if a:0 != 0
            set cmdheight=2
        endif
        call PVLErrorMessage("Found " . errors . " line error" . errorsplural . 
                    \", " . errmessages . " error message" . errmessagesplural . 
                    \" and " . warnings . " warning" . warningsplural . " in log file")
        if a:0 != 0
            set cmdheight=1
        endif
    endif
    return errors
endfunction

function! PVLDisplayFirstError()
        let errline = 0
        let errline = system("cat \"" . PVLLogFile() . "\" | grep \"" . b:texfile
                    \. ":\" | head -n1 | cut -d \":\" -f 2 | tr -d '\n'")
        let errmsg = system("cat \"" . PVLLogFile() . "\" | grep \""
                    \. b:texfile . ":\" | head -n1 | sed \"s/[^:]*:[^:]*: //\" | tr -d '\n'")
        
        if errline > 0
            exec ":" . errline
            call PVLErrorMessage("Error on line " . errline . ": " . errmsg)
        else
            " look for errors in other files
            let errfile = system("cat \"" . PVLLogFile() . "\" | grep \""
                    \. ".tex:\" | head -n1 | cut -d \":\" -f 1 | tr -d '\n'")
            let errline = system("cat \"" . PVLLogFile() . "\" | grep \""
                    \. ".tex:\" | head -n1 | cut -d \":\" -f 2 | tr -d '\n'")
            let errmsg = system("cat \"" . PVLLogFile() . "\" | grep \""
                    \. ".tex:\" | head -n1 | sed \"s/[^:]*:[^:]*: //\" | tr -d '\n'")

            if errline > 0
                call PVLErrorMessage("Error in file " . errfile . " on line " . errline . ": " . errmsg)
            else
                let errmessages = system("cat \"" . PVLLogFile() . "\" | grep \"\^\!\" | wc -l | tr -d '\n' ")
                if errmessages == "0"
                    call PVLMessage("No errors found in log file")
                else
                    call PVLMessage("No errors with line numbers found, but check error messages.")
                endif
            endif
        endif

endfunction

function! PVLDisplayErrors()
    " Get list of errors
    let lineerrors = system("cat \"" . PVLLogFile() . "\" | grep \".tex:\" | head -n -1")
    let lineerrors = lineerrors . system("cat \"" . PVLLogFile() . "\" | grep \".tex:\" | tail -n 1 | tr -d '\n'")

    
    if lineerrors == ""
        call PVLMessage("No line errors found in log file")    
    else
        call PVLErrorMessage("Line errors found in log file:")    
        echohl Normal | echo lineerrors
    endif
    
    return 0
endfunction



function! PVLDisplayMessages()
    " Get list of messages
    let errmessages = system("cat \"" . PVLLogFile() . "\" | grep \"\^\!\" | "
                \. " head -n -1 ")
    let errmessages = errmessages . system("cat \"" . PVLLogFile() . "\" | "
                \. "grep \"\^\!\" | tail -n 1 | tr -d '\n'")

    if errmessages == ""
        call PVLMessage("No error messages found in log file")    
    else
        call PVLErrorMessage("Error messages found in log file:")    
        echohl Normal | echo errmessages
    endif
    
    return 0
endfunction



function! PVLDisplayWarnings()
    " Get list of warnings
    let warnings = system("cat \"" . PVLLogFile() . "\" | grep \"LaTeX Warning:\" | "
                \. " head -n -1 ")
    let warnings = warnings . system("cat \"" . PVLLogFile() . "\" | "
                \. "grep \"LaTeX Warning:\" | tail -n 1 | tr -d '\n'")

    if warnings == ""
        call PVLMessage("No warnings found in log file")    
    else
        call PVLErrorMessage("Warnings found in log file:")    
        echohl Normal | echo warnings
    endif
    
    return 0
endfunction




" check for rerun crossreferences rerun warning
" disable prompt by setting PVL_references_noprompt

function! PVLCheckCrossreferencesWarning()
    let labelstr = "LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right."
    let warnings = system("cat \"" . PVLLogFile() . "\" | grep \"" . labelstr . "\" | wc -l | tr -d '\n'")
    
    if warnings == "1"
        if !g:PVLReferenceWarningPrompt
            let rerun = "1"
            set cmdheight=2
            call PVLMessage("Found \"Label(s) may have changed\" warning. Recompiling to update cross-references.")
        else 
            let rerun = confirm(b:msgprefix . "Found \"Label(s) may have changed\" warning. Recompile to update cross-references? ", "&Y\n&\N", 1)
        endif
        if rerun == "1"
            call PVLCompilePDF()
            set cmdheight=1
            return 1
        endif
    endif
    return 0
endfunction



" Displays log file in split
function! PVLViewLogFile()
    if filereadable(PVLLogFile())
        exec ":sp " . substitute(PVLLogFile(),'\s',"\\\\\ ", "g") . ""
    else
        call PVLErrorMessage("No log file found")    
    endif
endfunction


" llpp controlling functions

" check if the process is running and variables are initialized
function! PVLCheckViewerStatus()

    if b:viewerpid == "999999"
        let b:windowid = "999999"
        return 0
    endif

    if b:windowid == "999999"
        let b:viewerid = "999999"
        return 0
    endif

    if !isdirectory("/proc/" . b:viewerpid)
        let b:windowid = "999999"
        let b:viewerpid = "999999"
        return 0
    endif

    return 1
endfunction


" Launch viewer via xdotool
" Fail if no pdf present
function! PVLLaunchViewer()
    if PVLCheckViewerStatus() == 1
        call PVLErrorMessage("Will not launch viewer as it is already running")
        return 1
    endif

     
    if !filereadable(PVLPdfFile())
        call PVLErrorMessage("Cannot launch viewer, no pdf file found")
        return 0 
    endif

    let slashedoutfile = substitute(b:tmpdir . "/viewerout.log",'\s',"\\\\\ ", "g") . ""
    
    " launch process
    let b:viewerpid = system("llpp \"" . PVLPdfFile() . "\" > " . slashedoutfile . "&; echo $! | tr -d '\n'")


    " grab window id by looping until xdotool finds it or the process dies
    let b:windowid = ""
    while b:windowid == ""

        let b:windowid = system("xdotool search --pid " . b:viewerpid . " --class MuPDF | tr -d '\n'")
        
        if !isdirectory("/proc/" . b:viewerpid)
            PVLErrorMessage("Failed to launch viewer")
                let b:windowid = "999999"
                let b:viewerpid = "999999"
            return 0
        endif
    endwhile

    call PVLMessage("Opened viewer with pid " . b:viewerpid . " and windowid " . b:windowid . ".")
    return 1
endfunction


" Close pdf viewer via xdotool
function! PVLCloseViewer()
    if PVLCheckViewerStatus() == 0
        call PVLErrorMessage("Will not close viewer as it is not running")
        return 1
    endif

    " close
    call system("xdotool windowkill " . b:windowid)
    
    " reset state
    let b:windowid = "999999"
    let b:viewerpid = "999999"
    
    call PVLMessage("Closed viewer.")
endfunction

" Toggle showing of viewer
" Promp for compile if no pdf is present
function PVLToggleViewer()
    if PVLCheckViewerStatus() == 0 
        let compilesuccess = 1
        if !filereadable(PVLPdfFile())
            let compile = confirm(b:msgprefix . "No pdf to display. Compile document? ", "&Y\n&\N", 1)
            if compile == "1"
                let compilesuccess = PVLCompilePDF()
            endif
        endif
        if compilesuccess == 1
            call PVLLaunchViewer()
        else
            call PVLErrorMessage("Compilation failed. Will not open viewer.")
        endif
    else
        call PVLCloseViewer()
    endif

endfunction

" updating function for both PDF and viewer
function! PVLUpdate()
    if PVLCompilePDF() == 0
        if PVLCheckViewerStatus() == 1
            call PVLErrorMessage("Displayed PDF is volatile! Reloading the viewer will close it!")
        endif
        return
    endif
    if PVLCheckViewerStatus() == 1
        call system("xdotool key --window " . b:windowid . " r &> /dev/null")
    endif
    call PVLCheckViewerStatus()
endfunction


" synctex integration
function! PVLSynctexView()
    let linenr = line(".")
    let colnr = virtcol(".")

    " check pdf file open and synctex file present
    if PVLCheckViewerStatus() == 0
        call PVLErrorMessage("Cannot perform synctex, viewer is not running.")
        return
    endif

    if !filereadable(b:tmpdir . "/" . b:texfilename . ".synctex.gz")
        call PVLErrorMessage("No Synctex file found.")
        return
    endif

    let slashedtexfile = substitute(b:texfile,'\s',"\\\\\ ", "g") . ""
    let slashedpdffile = substitute(PVLPdfFile(),'\s',"\\\\\ ", "g") . ""
    let syncstring = "synctex view -i " . linenr . ":" . colnr . ":" . slashedtexfile
                \. " -o " . slashedpdffile.  "| grep Page | tail -n 1 | tr -d '\n' | tr -d 'Page:'"
    
    let page = system(syncstring)

    if page == ""
        call PVLMessage("Synctex gave no page number for position " . linenr . ":" . colnr)
        return
    end

    let chars = split(page,'\zs')

    for char in chars
        call system("xdotool key --window " . b:windowid . " " . char . " &> /dev/null")
    endfor

    call system("xdotool key --window " . b:windowid . " KP_Enter &> /dev/null")
    
    call PVLMessage("Executed Synctex on position " . linenr . ":" . colnr . " and went to page " . page)
endfunction


function! PVLSynctexEdit()

    
    let slashedoutfile = substitute(b:tmpdir . "/viewerout.log",'\s',"\\\\\ ", "g") . ""
    let slashedpdffile = substitute(PVLPdfFile(),'\s',"\\\\\ ", "g") . ""
    
    if !filereadable(b:tmpdir . "/" . b:texfilename . ".synctex.gz")
        call PVLErrorMessage("No Synctex file found.")
        return
    endif

    if !filereadable(b:tmpdir . "/viewerout.log")
        call PVLErrorMessage("No viewer log file found.")
        return
    end
    
    " get coordinates from pdf
    let coordstring =  system("cat " . slashedoutfile . " | tail -n 1")
    

    if coordstring == ""
        call PVLErrorMessage("No recent Synctex coordinates provided by viewer.")
        return
    end
  
    let coordarr = split(coordstring)

    let synctexcmd = "synctex edit -o " . (coordarr[-3]+1) . ":" . coordarr[-2] . ".0:" . coordarr[-1]
                \. ".0:" . slashedpdffile

    
    " extract parameters
    let file = substitute(system(synctexcmd . " | grep Input | tail -n 1 | tr -d '\n'"),"Input:","",'g')

    let linenr = system(synctexcmd . " | grep Line | tail -n 1 | tr -d 'Line:' | tr -d '\n'")

    let columnnr = system(synctexcmd . " | grep Column | tail -n 1 | tr -d 'Column:' | tr -d '\n'")

    " check if in different file
    if file != b:texfile
        call PVLErrorMessage("Synctex points to file " . file . ":" . linenr . ":" . columnnr . ".")
        return
    end


    " go to position
    exec ":" . linenr
    
    if columnnr < 0
        let columnnr = ""
        let lineannot = "on line "
    else 
        exec columnnr ."|"
        let columnnr = ":" . columnnr
        let lineannot = "at "
    end

    call PVLMessage("Went to most recent Synctex coordinate " . lineannot . linenr . columnnr)

endfunction




" initialize globals
call PVLInitGlobals()

" set no_plugin_maps or no_tex_maps to disable keybindings and autocommands
if !exists("no_plugin_maps") && !exists("no_tex_maps")
    " default keybindings

    nnoremap <silent> <buffer> <LocalLeader>q :call PVLToggleViewer()<CR>
    nnoremap <silent> <buffer> <LocalLeader>r :call PVLUpdate()<CR>
    nnoremap <silent> <buffer> <LocalLeader>x :call PVLExportPDF()<CR>
    nnoremap <silent> <buffer> <LocalLeader>p :call PVLPrint()<CR>

    nnoremap <silent> <buffer> <LocalLeader>l :call PVLViewLogFile()<CR>
    
    nnoremap <silent> <buffer> <LocalLeader>c :call PVLCountErrorsAndWarnings()<CR>
    nnoremap <silent> <buffer> <LocalLeader>e :call PVLDisplayErrors()<CR>
    nnoremap <silent> <buffer> <LocalLeader>m :call PVLDisplayMessages()<CR>
    nnoremap <silent> <buffer> <LocalLeader>w :call PVLDisplayWarnings()<CR>
    
    nnoremap <silent> <buffer> <LocalLeader>f :call PVLDisplayFirstError()<CR>
    
    nnoremap <silent> <buffer> <LocalLeader>v :call PVLSynctexView()<CR>
    nnoremap <silent> <buffer> <LocalLeader>s :call PVLSynctexEdit()<CR>
    
    
    " auto commands
    autocmd BufWritePost *.tex call PVLUpdate()
    autocmd VimLeave *.tex silent call PVLCloseViewer()

endif


