#' Use Default .gitignore File
#'
#' Copies the grkmisc default .gitignore file into the provided directory.
#'
#' @param directory Directory for the .gitignore, defaults to project root.
#' @param browse Open the .gitignore file after modifying?
#' @param overwrite Should existing file be overwritten?
#' @export
use_grk_gitignore <- function(
  directory = here::here(),
  browse = TRUE,
  overwrite = NULL
) {
  proj_gitignore <- file.path(directory, ".gitignore")
  default_gitignore <- system.file("templates", "_gitignore", package = "grkmisc")
  if (!file.exists(default_gitignore)) {
    rlang::abort(paste(
      ".gitignore template is missing from your installation of `grkmisc`.",
      "You may need to reinstall `grkmisc`.",
      "\nYou can also view the .gitignore template online at:",
      "\nhttps://github.com/GerkeLab/grkmisc/blob/master/inst/templates/.gitignore"
    ))
  }
  overwrite <- overwrite %||% yesno::yesno(
    "Overwrite .gitignore? Select no to append to existing .gitignore file"
  )
  append <- file.exists(proj_gitignore) && !overwrite
  cat(readLines(default_gitignore), sep = "\n", file = proj_gitignore, append = append)
  if (append) {
    cli::cat_bullet("Adding: grkmisc ", crayon::blue("'.gitignore'"),
                    " to existing ", crayon::blue("'.gitignore'"),
                    bullet = "tick", bullet_col = "green")
  } else {
    cli::cat_bullet("Writing default ", crayon::blue("'.gitignore'"),
                    bullet = "tick", bullet_col = "green")
  }
  if (browse && rstudioapi::isAvailable()) rstudioapi::navigateToFile(proj_gitignore)
  invisible(TRUE)
}

#' Use grkmisc git Pre-Commit Hook
#'
#' Installs a pre-commit hook that automatically bumps the lowest part of the
#' package version before committing - for example from `0.1.2.9000` to
#' `0.1.2.90001` - and tidies up the DESCRIPTION file using
#' [usethis::use_tidy_description]. If the version was manually changed as part
#' of the commit, the version number is not changed. If changes were made to the
#' DESCRIPTION file but this file was not committed, those additional changes
#' will be committed with the version bump.
#'
#' @section Disabling the hook:
#' You can disable the pre-commit hook in two ways. First you can set an
#' environment variable when committing your files:
#' `doIncrement=FALSE git commit -m "commit message"`. Alternatively, you can
#' skip the pre-commit hook with `git commit --no-verify -m "commit message"`.
#'
#' @export
use_git_hook_precommit <- function() {
  usethis::use_git_hook(
    "pre-commit",
    readLines(system.file("templates", "pre-commit.R", package = "grkmisc"))
  )
}

#' Create a default package skeleton
#'
#' @section Default Package Description:
#' See [usethis::use_description()] for information about setting your default
#' package DESCRIPTION file fields. The help file there provides an example of
#' how to set `"usethis.description"` in your `.Rprofile`.
#'
#' @param path Path (and thus package name) where the package will be stored
#' @param github Should a github repository be created?
#' @param github_org The organization where the repo should be created. If
#'   unspecified (or `NULL`), the default is to create the package in your
#'   personal account.
#' @param github_private Should the GitHub repo be private?
#' @param open Should the package be opened? If `TRUE`, tries to open in RStudio
#'   and falls back to changing the working directory.
#' @param title Package title: "What the Package Does (One Line, Title Case)"
#' @param description Package description: "What the package does (one
#'   paragraph)"
#' @export
use_grk_starter_package <- function(
  path,
  github = TRUE,
  github_org = NULL,
  github_private = FALSE,
  open = TRUE,
  title = "What the Package Does (One Line, Title Case)",
  description = "What the package does (one paragraph)"
) {
  required_pkgs <- setdiff(
    c("spelling", "roxygen2"),
    utils::installed.packages()[, "Package"]
  )
  if (length(required_pkgs)) {
    utils::install.packages(required_pkgs)
  }
  usethis::create_package(
    path, open = FALSE, rstudio = TRUE,
    fields = list(
      Title = title,
      Description = description
    ))
  owd <- setwd(path)
  usethis::proj_set(path)
  usethis::use_roxygen_md()
  usethis::use_readme_rmd(open = FALSE)
  done("Writing NEWS.md")
  pkg_data <- usethis:::package_data()
  cat(glue::glue(
    "## {pkg_data$Package} {pkg_data$Version}

    * Initialized {pkg_data$Package} package
    "
  ), file = "NEWS.md")
  usethis::use_testthat()
  usethis::use_spell_check()
  usethis::use_pipe()
  if (in_rstudio_project() || is_usethis_recent()) {
    usethis::use_blank_slate("project")
  }
  usethis::use_directory("data-raw")
  done("Updating package documentation")
  if (suggest_package("devtools")) {
    devtools::document(usethis::proj_get())
  }
  use_grk_gitignore(browse = FALSE, overwrite = TRUE)
  done("Initializing git repo")
  repo <- git2r::init(usethis::proj_get())
  use_git_hook_precommit()
  if (github) {
    safe_github <- purrr::safely(usethis::use_github)
    rs <- safe_github(organisation = github_org, private = github_private)
    ok <- FALSE
    if (!is.null(rs$error)) {
      cli::cat_bullet(crayon::red("Error: "),
                      stringr::str_trim(rs$error$message, side = "right"),
                      bullet_col = "red")
      ok <- !grepl("GitHub API error", rs$error$message)
    }
    if (ok) {
      # Something went wrong with GitHub repo start up...but it probably wasn't fatal
      usethis::use_github_links()
      usethis::use_github_labels(delete_default = TRUE)
    }
  }

  # Initial commit
  paths <- unlist(git2r::status(repo))
  ask_commit_msg <- glue::glue("OK to make initial commit of {length(paths)} files?")
  if (yesno::yesno(ask_commit_msg)) {
    done("Adding files and committing")
    git2r::add(repo, paths)
    git2r::commit(repo, "Initialize package")
  }

  if (open && rstudioapi::hasFun("openProject")) {
    done("Opening project in RStudio")
    rproj_path <- dir(path, pattern = "Rproj")
    rstudioapi::openProject(rproj_path, newSession = TRUE)
    usethis::proj_set(owd)
  } else if (open) {
    done("Working directory set to new package directory")
  } else {
    done("Package created in ", path)
    setwd(owd)
  }
  invisible(TRUE)
}

#' Create a default project skeleton
#'
#' Uses [usethis] to create an empty project, with an RStudio project file and
#' an initialized git repository in the specified path.
#'
#' @param path Path where the project will be started
#' @export
use_grk_starter_project <- function(path) {
  usethis::create_project(path, rstudio = TRUE)
  usethis::use_blank_slate("project")
  usethis::use_readme_rmd(FALSE)
  done("Writing ", crayon::blue("'NEWS.md'"))
  news_md <- c("# News\n", strftime(Sys.time(), "## %F"), "\nProject Started")
  cat(news_md, file = file.path(usethis::proj_get(), "NEWS.md"), sep = "\n")
  git2r::init(usethis::proj_get())
  done("Project started in ", path)
}

in_rstudio_project <- function() {
  if (!requireNamespace("rstudioapi", quietly = TRUE)) return(FALSE)
  if (!rstudioapi::hasFun("getActiveProject")) return(FALSE)
  if (is.null(rstudioapi::getActiveProject())) return(FALSE)
  TRUE
}

is_usethis_recent <- function() {
  package_version(utils::packageVersion("usethis")) >= "1.4.0.9000"
}

#' Setup GerkeLab Default GitHub Labels
#'
#' Removes the default GitHub labels and installs the GerkeLab labels. A small
#' wrapper around [usethis::use_github_labels()].
#'
#' @inheritDotParams usethis::use_github_labels
#' @inheritParams usethis::use_github_labels
#' @export
use_grk_github_labels <- function(
  ...,
  labels = grk_github_labels(),
  colours = grk_github_colours(),
  descriptions = grk_github_descriptions(),
  delete_default = TRUE
) {
  usethis::use_github_labels(
    ...,
    labels = labels,
    colours = colours,
    descriptions = descriptions,
    delete_default = delete_default
  )
}

#' @describeIn use_grk_github_labels Default grkmisc GitHub labels.
#' @export
grk_github_labels <- function() {
  c(
    "planning :seedling:",
    "feature :hatching_chick:",
    "question :question:",
    "documentation :memo:",
    "bug :bug:",
    "duplicate",
    ":construction: WIP :construction:",
    "considering :thinking:"
  )
}

#' @describeIn use_grk_github_labels Default grkmisc GitHub colours.
#' @export
grk_github_colours <- function() {
  c(
    "planning :seedling:" = "BFDADC",
    "feature :hatching_chick:" = "B5DDA4",
    "question :question:" = "99ADC2",
    "documentation :memo:" = "3E363F",
    "bug :bug:" = "754668",
    "duplicate" = "CFD3D7",
    ":construction: WIP :construction:" = "FBCA04",
    "considering :thinking:" = "BF1349"
  )
}

#' @describeIn use_grk_github_labels Default grkmisc GitHub descriptions.
#' @export
grk_github_descriptions <- function() {
  c(
    "planning :seedling:" = "Development planning",
    "feature :hatching_chick:" = "New functionality!",
    "question :question:" = "Need help or more information",
    "documentation :memo:" = "Documentation improvement, clarification, or update",
    "bug :bug:" = "Something isn't working",
    "duplicate" = "This issue or pull request already exists",
    ":construction: WIP :construction:" = "Work in Progress! Don't Merge!",
    "considering :thinking:" = "Let's think about this..."
  )
}
