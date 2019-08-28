# Azure analytics scan [Work in Progress!]


The goal of the scan is to gain insights into the structure used in an azure devops organisation and represent that in a graphical way preferabbly in an extension.

**Questions we like to be answered with the scan:**

- How many repositories are there and how many commits where done in the past X days.
- Which builds use what repositories
- What repositories are used by which pipelines.
- The artifacts used in a build are used by what pipelines.
- What artifacts go to which artifact repositories
- etc

The outcome of the scan are a set of json files with guid\id references to map to the other files. During the visualisation tie everything together.
For visualisation we looked to https://github.com/strathausen/dracula

![image.png](.attachments\azdo-example.png)
