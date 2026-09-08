// Every controller the console serves, by the name its markup uses.
//
// Registration is unconditional and costs nothing until an element asks for a
// controller, so a page carries the whole set whether or not it uses any of
// it. The libraries these drive are the expensive part, and those a page still
// asks for by name — see BaseLayout::BUNDLES.
application.register("app-shell", AppShellController)
application.register("auto-refresh", AutoRefreshController)
application.register("auto-submit", AutoSubmitController)
application.register("check-sampling", CheckSamplingController)
application.register("diff", DiffController)
application.register("evaluator-toggle", EvaluatorToggleController)
application.register("experiment-edit", ExperimentEditController)
application.register("json-highlight", JsonHighlightController)
application.register("policy-agent", PolicyAgentController)
application.register("poll", PollController)
application.register("prompt-editor", PromptEditorController)
application.register("replay-form", ReplayFormController)
application.register("span-detail", SpanDetailController)
application.register("tooltip", TooltipController)
