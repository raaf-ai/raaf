// The console's Stimulus runtime.
//
// Every file under this directory is concatenated into one ES module and
// served by RAAF::Rails::AssetsController — see RAAF::Rails::Ui::Javascript
// for why the engine delivers its own JavaScript rather than asking the host
// application for a pipeline. The consequence for these files is that they
// share a single module scope: there are no `import`/`export` statements
// between them, and `application` and `Controller` are simply in scope
// everywhere below. This is the bundle's only import, so it comes first.
import { Application, Controller } from "https://unpkg.com/@hotwired/stimulus/dist/stimulus.js"

const application = Application.start()
