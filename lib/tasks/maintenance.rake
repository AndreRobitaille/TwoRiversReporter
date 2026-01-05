namespace :maintenance do
  desc "Re-analyze all PDFs to populate Extractions and trigger Summaries"
  task reanalyze_pdfs: :environment do
    docs = MeetingDocument.where("document_type LIKE ?", "%pdf%")
    puts "Found #{docs.count} PDF documents to re-analyze..."

    docs.find_each do |doc|
      next unless doc.file.attached?
      puts "Re-analyzing Document #{doc.id} (#{doc.document_type})..."
      Documents::AnalyzePdfJob.perform_now(doc.id)
    end
    puts "Done."
  end
end
