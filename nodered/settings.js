module.exports = {
    flowFile: 'flows.json',
    flowFilePretty: true,
    uiPort: process.env.PORT || 1880,

    adminAuth: {
        type: "credentials",
        users: [{
            username: "admin",
            password: "$2b$08$BAHOFBwYP6/JqRZpH2v92eEERWwb/jggyXk4iTsCqGmathVlr6SMK",
            permissions: "*"
        }]
    },

    functionExternalModules: true,
    functionGlobalContext: {},
    exportGlobalContextKeys: false,

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    editorTheme: {
        projects: { enabled: false },
        codeEditor: { lib: "monaco" }
    }
};
