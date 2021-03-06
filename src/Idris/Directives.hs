
module Idris.Directives(directiveAction) where

import Idris.AbsSyntax
import Idris.ASTUtils
import Idris.Imports
import Idris.Output (sendHighlighting)

import Idris.Core.Evaluate
import Idris.Core.TT

import Util.DynamicLinker

-- | Run the action corresponding to a directive
directiveAction :: Directive -> Idris ()
directiveAction (DLib cgn lib) = do addLib cgn lib
                                    addIBC (IBCLib cgn lib)

directiveAction (DLink cgn obj) = do dirs <- allImportDirs
                                     o <- runIO $ findInPath dirs obj
                                     addIBC (IBCObj cgn obj) -- just name, search on loading ibc
                                     addObjectFile cgn o

directiveAction (DFlag cgn flag) = do
                                      let flags = words flag
                                      mapM_ (\f -> addIBC (IBCCGFlag cgn f)) flags
                                      mapM_ (addFlag cgn) flags

directiveAction (DInclude cgn hdr) = do addHdr cgn hdr
                                        addIBC (IBCHeader cgn hdr)

directiveAction (DHide n) = do setAccessibility n Hidden
                               addIBC (IBCAccess n Hidden)

directiveAction (DFreeze n) = do setAccessibility n Frozen
                                 addIBC (IBCAccess n Frozen)

directiveAction (DAccess acc) = do updateIState (\i -> i { default_access = acc })

directiveAction (DDefault tot) =  do updateIState (\i -> i { default_total = tot })

directiveAction (DLogging lvl) = setLogLevel (fromInteger lvl)

directiveAction (DDynamicLibs libs) = do added <- addDyLib libs
                                         case added of
                                             Left lib -> addIBC (IBCDyLib (lib_name lib))
                                             Right msg -> fail $ msg

directiveAction (DNameHint ty tyFC ns) = do ty' <- disambiguate ty
                                            mapM_ (addNameHint ty' . fst) ns
                                            mapM_ (\n -> addIBC (IBCNameHint (ty', fst n))) ns
                                            sendHighlighting $
                                              [(tyFC, AnnName ty' Nothing Nothing Nothing)] ++
                                              map (\(n, fc) -> (fc, AnnBoundName n False)) ns

directiveAction (DErrorHandlers fn nfc arg afc ns) =
  do fn' <- disambiguate fn
     ns' <- mapM (\(n, fc) -> do n' <- disambiguate n
                                 return (n', fc)) ns
     addFunctionErrorHandlers fn' arg (map fst ns')
     mapM_ (addIBC .
         IBCFunctionErrorHandler fn' arg . fst) ns'
     sendHighlighting $
       [(nfc, AnnName fn' Nothing Nothing Nothing),
        (afc, AnnBoundName arg False)] ++
       map (\(n, fc) -> (fc, AnnName n Nothing Nothing Nothing)) ns'

directiveAction (DLanguage ext) = addLangExt ext
directiveAction (DDeprecate n reason) 
    = do n' <- disambiguate n
         addDeprecated n' reason
         addIBC (IBCDeprecate n' reason)
directiveAction (DAutoImplicits b)
    = setAutoImpls b
directiveAction (DUsed fc fn arg) = addUsedName fc fn arg

disambiguate :: Name -> Idris Name
disambiguate n = do i <- getIState
                    case lookupCtxtName n (idris_implicits i) of
                              [(n', _)] -> return n'
                              []        -> throwError (NoSuchVariable n)
                              more      -> throwError (CantResolveAlts (map fst more))
