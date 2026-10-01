# Textos das tabelas interativas (reactable) em português do Brasil.
# Carregado por R/funcoes.R; não precisa ser chamado diretamente pelas páginas.
options(reactable.language = reactable::reactableLang(
  sortLabel = "Ordenar por {name}", filterPlaceholder = "Filtrar", filterLabel = "Filtrar {name}",
  searchPlaceholder = "Buscar", searchLabel = "Buscar na tabela", noData = "Nenhum registro encontrado",
  pageNext = "Próxima", pagePrevious = "Anterior", pageNumbers = "{page} de {pages}",
  pageInfo = "{rowStart}–{rowEnd} de {rows} linhas", pageSizeOptions = "Mostrar {rows}",
  pageNextLabel = "Próxima página", pagePreviousLabel = "Página anterior",
  pageNumberLabel = "Página {page}", pageJumpLabel = "Ir para a página",
  pageSizeOptionsLabel = "Linhas por página", groupExpandLabel = "Expandir grupo",
  detailsExpandLabel = "Mostrar detalhes", selectAllRowsLabel = "Selecionar todas as linhas",
  selectAllSubRowsLabel = "Selecionar todas as linhas do grupo", selectRowLabel = "Selecionar linha"))
