module AdminHelper
  def sort_link(column, title = nil)
    title ||= column.titleize
    direction = column == params[:sort] && params[:direction] == "asc" ? "desc" : "asc"
    icon = sort_icon(column)
    link_to(request.query_parameters.merge(sort: column, direction: direction), class: "sort-link") do
      concat title
      concat icon
    end
  end

  def sort_icon(column)
    return unless column == params[:sort]

    if params[:direction] == "asc"
      # Chevron Up
      raw('<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="icon icon--sm"><path stroke-linecap="round" stroke-linejoin="round" d="m4.5 15.75 7.5-7.5 7.5 7.5" /></svg>')
    else
      # Chevron Down
      raw('<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="icon icon--sm"><path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" /></svg>')
    end
  end
end
